// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Building one function's e-graph: the classification by declared effects,
// the walk that puts each op in a class or in its region's skeleton and
// then saturates the classes under the rules, the sweep of what the
// write-back left unused, and the skeleton rules' decisions. The tables
// the walk fills are made in Nodes.cpp, the rounds run in Rules.cpp.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/Matchers.h"
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
// region op, an op of several results, and a call nothing of its caller
// may follow (a tail call, and a self call modulo a context), whose fact a
// promise reads.
bool staysPut(Operation *op) {
  return op->hasTrait<OpTrait::IsTerminator>() || op->getNumRegions() != 0 ||
         op->getNumResults() != 1 || lastActOf(op);
}

} // namespace

//===----------------------------------------------------------------------===//
// The walk
//===----------------------------------------------------------------------===//

Function::Function(idr::FuncOp fn, const Kinds &kinds, const CalleeFacts *callees)
    : fn(fn), kinds(kinds), callees(callees), numbering(fn),
      classOf(numbering.size(), std::optional<ClassId>()) {
  std::uint64_t ops = 0, read = 0;
  fn.getBody().walk([&](Operation *op) {
    ++ops;
    read += op->getNumOperands();
  });
  budget = std::uint64_t(nodesPerOp()) * std::max<std::uint64_t>(ops, 1);
  heldOperands = read + budget * widestSide();
  constantBytes = budget * bytesPerNode;
  slots.resize(64);
}

void Function::build() {
  RegionId body = newRegion({std::nullopt, 0, &fn.getBody(), {}, {}});
  for (BlockArgument arg : fn.getBody().getArguments())
    classOf[numbering.at(arg)] = leaf(arg, body);

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
  // each region op it is inside. An op's regions are numbered one after
  // another when the walk first enters the op, before any region nested in
  // them, so its k-th region is its first's number plus k.
  footprint::Vector<RegionId> open{body};
  footprint::Vector<RegionId> firstRegions;

  // An op's operands' classes at their roots, so two ops of one value's
  // operands compare equal however their classes were united.
  auto classesOf = [&](Operation *op) {
    SmallVector<ClassId, 4> operands;
    for (Value operand : op->getOperands())
      operands.push_back(forest.find(*classOf[numbering.at(operand)]));
    return operands;
  };

  for (Operation &top : fn.getBody().front())
    top.walk([&](Operation *op, const WalkStage &stage) {
      if (!stage.isAfterAllRegions()) {
        // A walk's stage counts regions as MLIR's int; an op's region is
        // found by its unsigned index.
        auto next = static_cast<unsigned>(stage.getNextRegion());
        if (next > 0)
          open.pop_back();
        if (next == 0) {
          RegionId parent = open.back();
          firstRegions.push_back(RegionId(static_cast<std::uint32_t>(regions.size())));
          for (mlir::Region &region : op->getRegions()) {
            (void)newRegion({parent, at(parent).depth + 1, &region, {}, {}});
            perRegion.emplace_back();
            mergeable.emplace_back();
          }
        }
        RegionId id(firstRegions.back().index() + next);
        open.push_back(id);
        for (Block &block : op->getRegion(next))
          for (BlockArgument arg : block.getArguments())
            classOf[numbering.at(arg)] = leaf(arg, id);
        return;
      }
      // A region op's first region, the walk's numbering of its regions.
      std::optional<RegionId> inner;
      if (op->getNumRegions() != 0) {
        open.pop_back();
        inner = firstRegions.back();
        firstRegions.pop_back();
      }
      RegionId region = open.back();
      effects::EffectSet does = effects::own(op);
      Entry entry = entryOf(op, does);
      if (!staysPut(op) && (entry == Entry::Floats || entry == Entry::OwnIdentity)) {
        SmallVector<ClassId, 4> operands = classesOf(op);
        Value result = op->getResult(0);
        // A constant op's own fold gives back the attribute it holds,
        // making none.
        Attribute constant;
        if (matchPattern(result, m_Constant(&constant))) {
          classOf[numbering.at(result)] = held(constant, result.getType(), op->getDialect(),
                                               intervalOf(op, operands));
          return;
        }
        Kinds::OfOp of = kinds.of(op);
        std::optional<MeaningOfInput> meaning;
        std::optional<GivenOfInput> given;
        if (of.meaning) {
          meaning = of.meaning->ofInput;
          given = of.meaning->given;
        }
        Identity identity = entry == Entry::OwnIdentity ? Identity::Own : Identity::Shared;
        // Whether its result is its operand's value, a trait of its class,
        // read once where its node is made, as its effects are.
        Keeps keeps = op->hasTrait<SameValue>() ? Keeps::Operand : Keeps::Nothing;
        classOf[numbering.at(result)] =
            insert(node::Input{op, of.kind, identity, keeps, meaning, given}, result.getType(),
                   operands);
        return;
      }
      // A skeleton op: its results are leaves. A repeated read with nothing
      // between that may change it is the first read: no op between, with
      // everything in its regions, conflicts with what the read does, which
      // changes nothing. A repeated op of the region's parent is the first.
      footprint::Vector<Skeletal> &list = perRegion[region.index()];
      footprint::Vector<Mergeable> &earlier = mergeable[region.index()];
      std::optional<Merged> merged;
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
            merged = Merged{first.op};
            break;
          }
        }
        if (!merged)
          earlier.push_back({op, static_cast<std::uint32_t>(list.size() + 1)});
      }
      if (merged) {
        for (auto [mine, theirs] : llvm::zip_equal(op->getResults(), merged->into->getResults()))
          classOf[numbering.at(mine)] = *classOf[numbering.at(theirs)];
        list.push_back({op, *merged, inner});
      } else {
        for (Value result : op->getResults())
          classOf[numbering.at(result)] = leaf(result, region);
        // A call's result is the constant its callee returns there, whatever
        // else the call does, or holds it at another grade, as its facts say;
        // but a call nothing of its caller may follow gives its caller's
        // results as they are, and a use of them taking a constant instead
        // would end the tail.
        if (auto call = dyn_cast<CallOp>(op); call && callees && !lastActOf(op))
          if (std::optional<solver::FunctionId> callee = callees->calleeOf(call))
            for (auto [index, result] : llvm::enumerate(op->getResults()))
              if (std::optional<Returned> returned =
                      returnedBy(*callee, call, static_cast<unsigned>(index))) {
                ClassId cls = *classOf[numbering.at(result)];
                match(
                    *returned, [&](ClassId constant) { (void)unite(cls, constant); },
                    [&](const Facts &said) { narrow(cls, said); });
              }
        list.push_back({op, Kept{}, inner});
      }
    });

  for (auto [at, list] : llvm::enumerate(perRegion)) {
    regions[at].skeleton = {static_cast<std::uint32_t>(skeleton.size()),
                            static_cast<std::uint32_t>(list.size())};
    llvm::append_range(skeleton, list);
  }

  connectRegions();
  saturate();
  settle();
}

// What the input's floating ops became: each was made again where it is
// demanded, or is demanded nowhere; and a value the write-back made for an
// op an edit then erased is demanded nowhere either. Every op that floats
// and is unused goes, users before what they use: one that floats has no
// effect to lose, and one with an identity is deletable when unused; so
// does an op of its parent no op uses, which has no effect either. So does
// an op the skeleton kept for its regions or its several results where it
// only computes, with everything in its regions, and no op uses what it
// gives: every result of it the graph found a constant, or none it has, as
// a region-branch op every use of whose results now takes the constants
// its running regions yield. The walk meets only ops still in the
// function, never one an edit erased with its region, an op after every op
// nested in it, so those nested in one that goes are the run just before
// it, which go with it.
void Function::sweep(RewriterBase &rewriter) {
  footprint::Vector<Operation *> ops;
  fn.getBody().walk([&](Operation *op) {
    Entry entry = entryOf(op, effects::own(op));
    if ((!staysPut(op) &&
         (entry == Entry::Floats || entry == Entry::OwnIdentity || entry == Entry::OfParent)) ||
        (!op->hasTrait<OpTrait::IsTerminator>() &&
         (op->getNumRegions() != 0 || op->getNumResults() != 1) &&
         effects::whole(op).onlyComputes()))
      ops.push_back(op);
  });
  for (std::size_t at = ops.size(); at-- > 0;) {
    Operation *op = ops[at];
    if (!op->use_empty())
      continue;
    std::size_t first = at;
    while (first > 0 && op->isProperAncestor(ops[first - 1]))
      --first;
    rewriter.eraseOp(op);
    at = first;
  }
}

//===----------------------------------------------------------------------===//
// Deciding
//===----------------------------------------------------------------------===//

// The skeleton rules, in the order the specification lists them, each
// asked of every skeleton op its root is, once the e-graph is extracted;
// the first that decides an edit has it. In the second turn a Rewrite is
// kept as it is.
void Function::decide(Turn turn) {
  OperandFacts facts(*this);
  for (Skeletal &entry : skeleton) {
    // A repeated read stays the earlier op's, and a function decides once.
    std::optional<Decided> decided =
        match(entry.fate, [&](Kept) { return decideSkeleton(entry.op, facts); },
              [](const Merged &) -> std::optional<Decided> { return std::nullopt; },
              [](const Decided &) -> std::optional<Decided> { return std::nullopt; });
    if (!decided)
      continue;
    bool stands = match(
        decided->edit, [&](const Rewrite &) { return turn == Turn::First; },
        [](const Forward &) { return true; }, [](const Take &) { return true; });
    if (stands)
      entry.fate = std::move(*decided);
  }
}

footprint::Vector<Function::Pending> Function::rewrites() const {
  footprint::Vector<Pending> out;
  for (const Skeletal &entry : skeleton)
    match(
        entry.fate, [](Kept) {}, [](const Merged &) {},
        [&](const Decided &decided) {
          match(
              decided.edit,
              [&](const Rewrite &rewrite) { out.push_back({entry.op, decided.rule, rewrite}); },
              [](const Forward &) {}, [](const Take &) {});
        });
  return out;
}

} // namespace idr::egraph::detail
