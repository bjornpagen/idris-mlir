// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Building one function's e-graph: the walk, the classification by declared
// effects, the hash-cons, the analyses, the rules at insertion, the
// skeleton and its rules.
#include "Engine.h"

#include "idr/IR/Effects/Query.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::egraph::detail {

//===----------------------------------------------------------------------===//
// Kinds
//===----------------------------------------------------------------------===//

std::optional<std::uint16_t> Kinds::kindOf(Operation *op) const {
  TypeID id = op->getName().getTypeID();
  auto it = llvm::lower_bound(byTypeId, std::pair(id, std::uint16_t(0)),
                              [](const auto &a, const auto &b) {
                                return a.first.getAsOpaquePointer() < b.first.getAsOpaquePointer();
                              });
  if (it == byTypeId.end() || it->first != id)
    return std::nullopt;
  return it->second;
}

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
// Minting
//===----------------------------------------------------------------------===//

NodeId Function::newNode(Node node) {
  ++steps;
  nodes.push_back(std::move(node));
  return NodeId(static_cast<std::uint32_t>(nodes.size() - 1));
}

ClassId Function::newClass(Class cls) {
  classes.push_back(std::move(cls));
  return ClassId(static_cast<std::uint32_t>(classes.size() - 1));
}

RegionId Function::newRegion(Region region) {
  regions.push_back(region);
  return RegionId(static_cast<std::uint32_t>(regions.size() - 1));
}

Function::Function(idr::FuncOp fn, const Kinds &kinds, const CalleeFacts *callees)
    : fn(fn), kinds(kinds), callees(callees), numbering(fn),
      classOf(numbering.size(), std::optional<ClassId>()) {
  std::uint64_t ops = 0;
  fn.getBody().walk([&](Operation *) { ++ops; });
  budget = std::uint64_t(nodesPerOp()) * std::max<std::uint64_t>(ops, 1);
  slots.resize(64);
}

//===----------------------------------------------------------------------===//
// The hash-cons
//===----------------------------------------------------------------------===//

// A node's key: its op, its type, its properties and its operands' classes.
// Two nodes of the input compare their properties through the op's own
// comparison; a node a rule made has the op's default properties, and is
// equal only to another such. A node with an identity has no key.
bool Function::sameKey(const Node &a, std::span<const ClassId> ac, const Node &b,
                       std::span<const ClassId> bc) {
  if (a.type != b.type || !std::ranges::equal(ac, bc))
    return false;
  const auto *x = std::get_if<node::Op>(&a.what);
  const auto *y = std::get_if<node::Op>(&b.what);
  if (!x || !y || x->name != y->name || x->identity == Identity::Own ||
      y->identity == Identity::Own)
    return false;
  if (!x->origin || !y->origin)
    return !x->origin && !y->origin;
  return x->origin->getRawDictionaryAttrs() == y->origin->getRawDictionaryAttrs() &&
         x->name.compareOpProperties(x->origin->getPropertiesStorage(),
                                     y->origin->getPropertiesStorage());
}

std::uint64_t Function::hashOf(const Node &node, std::span<const ClassId> operands) const {
  const auto &op = std::get<node::Op>(node.what);
  llvm::hash_code hash = llvm::hash_combine(op.name.getAsOpaquePointer(),
                                            node.type.getAsOpaquePointer());
  for (ClassId operand : operands)
    hash = llvm::hash_combine(hash, operand.index());
  if (op.origin)
    hash = llvm::hash_combine(hash, op.origin->hashProperties());
  return static_cast<std::uint64_t>(hash);
}

// The table is probed, never iterated for a result, so what an address
// adds to a hash moves only where a key sits, never what is found.
std::optional<ClassId> Function::lookup(const Node &node) const {
  std::span<const ClassId> operands = childrenOf(node);
  std::uint64_t mask = slots.size() - 1;
  for (std::uint64_t at = hashOf(node, operands) & mask;; at = (at + 1) & mask) {
    const Slot &slot = slots[at];
    if (!slot.node)
      return std::nullopt;
    const Node &there = this->at(*slot.node);
    if (sameKey(node, operands, there, childrenOf(there)))
      return slot.cls;
  }
}

void Function::remember(NodeId n, ClassId cls) {
  if (2 * (filled + 1) > slots.size()) {
    std::vector<Slot> old = std::move(slots);
    slots.assign(old.size() * 2, Slot{});
    filled = 0;
    for (const Slot &slot : old)
      if (slot.node)
        remember(*slot.node, *slot.cls);
  }
  const Node &node = at(n);
  std::uint64_t mask = slots.size() - 1;
  std::uint64_t place = hashOf(node, childrenOf(node)) & mask;
  while (slots[place].node)
    place = (place + 1) & mask;
  slots[place] = {n, cls};
  ++filled;
}

//===----------------------------------------------------------------------===//
// Nodes and classes
//===----------------------------------------------------------------------===//

ClassId Function::alone(Node node, ClassId into) {
  members.push_back(newNode(std::move(node)));
  Class &cls = at(into);
  cls.members = {static_cast<std::uint32_t>(members.size() - 1), 1};
  return into;
}

ClassId Function::leaf(Value value) {
  ClassId cls = newClass({{}, value.getType(), Attribute(), std::nullopt});
  alone({node::Leaf{value}, value.getType(), {}}, cls);
  if (Attribute known; matchPattern(value, m_Constant(&known)))
    at(cls).constant = known;
  return cls;
}

ClassId Function::constant(Attribute value, Type type, Dialect *dialect) {
  ClassId cls = newClass({{}, type, value, std::nullopt});
  alone({node::Constant{value, dialect}, type, {}}, cls);
  if (auto integer = dyn_cast<IntegerAttr>(value))
    at(cls).range = ConstantIntRanges::constant(integer.getValue());
  return cls;
}

// A class's analyses from its one node: the constant its op folds to when
// every operand is a constant (the op of the input, folded with constant
// operands only, so its fold cannot rewrite it), and the interval
// upstream's transfer function gives its operands' intervals.
void Function::analyse(Class &cls, const Node &node) {
  const auto &op = std::get<node::Op>(node.what);
  if (!op.origin)
    return;
  std::span<const ClassId> operands = childrenOf(node);
  SmallVector<Attribute, 4> constants;
  for (ClassId operand : operands)
    constants.push_back(at(operand).constant);
  if (llvm::all_of(constants, [](Attribute a) { return static_cast<bool>(a); })) {
    SmallVector<OpFoldResult, 1> folded;
    if (succeeded(op.origin->fold(constants, folded)) && folded.size() == 1)
      if (auto attr = dyn_cast_if_present<Attribute>(folded.front()))
        cls.constant = attr;
  }
  // A node of the input reads its operands as the op's own operands, so an
  // operand with no known interval is its value's whole range.
  if (auto ranges = dyn_cast<InferIntRangeInterface>(op.origin)) {
    SmallVector<IntegerValueRange, 4> inputs;
    for (auto [operand, value] : llvm::zip_equal(operands, op.origin->getOperands())) {
      const Class &input = at(operand);
      inputs.push_back(input.range ? IntegerValueRange(*input.range)
                                   : IntegerValueRange::getMaxRange(value));
    }
    ranges.inferResultRangesFromOptional(inputs, [&](Value, const IntegerValueRange &result) {
      if (!result.isUninitialized())
        cls.range = result.getValue();
    });
  }
}

// The class of a floating op over `operands`: an equal node's class, found
// in the hash-cons; or a new node, its analyses computed and the rules
// rooted at its kind run on it, in the class those decide: a constant's
// when it folds, an argument's when its callee gives that back, a right
// side's when a Simplify rule matches, a new class of it and a right side
// when an Equal rule does, else a class of its own. None once the
// function's budget of nodes is spent, for a node a rule asked for: the
// form is then kept as it was, less optimized.
std::optional<ClassId> Function::insert(OperationName name, std::optional<std::uint16_t> kind,
                                        Operation *origin, Identity identity, Type type,
                                        std::span<const ClassId> operands, Rules rules) {
  Run run{static_cast<std::uint32_t>(children.size()), static_cast<std::uint32_t>(operands.size())};
  children.insert(children.end(), operands.begin(), operands.end());
  Node node{node::Op{name, kind, origin, identity}, type, run};
  if (identity == Identity::Shared)
    if (std::optional<ClassId> found = lookup(node)) {
      children.resize(run.first);
      return found;
    }
  if (!origin && nodes.size() >= budget) {
    children.resize(run.first);
    return std::nullopt;
  }
  NodeId made = newNode(std::move(node));
  Class analysed{{}, type, Attribute(), std::nullopt};
  analyse(analysed, at(made));

  auto decided = [&]() -> ClassId {
    if (analysed.constant && origin)
      return constant(analysed.constant, type, origin->getDialect());
    if (std::optional<ClassId> given =
            giveBack(std::get<node::Op>(at(made).what), operands, type))
      return *given;
    Rewritten rewritten = rules == Rules::Run ? rewrite(made, analysed) : Rewritten(NoRule{});
    if (const auto *replace = std::get_if<Replace>(&rewritten))
      return replace->by;
    Run joined{static_cast<std::uint32_t>(members.size()), 1};
    members.push_back(made);
    // The joined class's members are copied from the array they are
    // appended to, so by position, with room made first: an iterator into
    // the array would not survive its growth.
    if (const auto *join = std::get_if<Join>(&rewritten)) {
      Run with = at(join->with).members;
      members.reserve(members.size() + with.count);
      for (std::uint32_t position = with.first; position < with.first + with.count; ++position) {
        NodeId member = members[position];
        members.push_back(member);
      }
      steps += with.count;
      joined.count = static_cast<std::uint32_t>(members.size()) - joined.first;
    }
    analysed.members = joined;
    return newClass(analysed);
  };
  ClassId cls = decided();
  if (identity == Identity::Shared)
    remember(made, cls);
  return cls;
}

// A floating call of a function that gives back one of its arguments whole,
// as the optimizer decided, is that argument: the call floats only where
// its row carries neither crash nor divergence, so nothing is lost with it.
std::optional<ClassId> Function::giveBack(const node::Op &op, std::span<const ClassId> operands,
                                          Type type) {
  if (!callees || !op.origin)
    return std::nullopt;
  auto call = dyn_cast<CallOp>(op.origin);
  if (!call)
    return std::nullopt;
  for (const identities::GivesBack &fact : callees->of(call.getCalleeAttr()))
    if (fact.result.index == 0 && fact.result.fields.empty() && fact.argument.fields.empty() &&
        at(operands[fact.argument.index]).type == type)
      return operands[fact.argument.index];
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// The walk
//===----------------------------------------------------------------------===//

void Function::build() {
  RegionId body = newRegion({std::nullopt, 0, &fn.getBody(), {}});
  for (BlockArgument arg : fn.getBody().getArguments())
    classOf[numbering.at(arg)] = leaf(arg);

  // Each region's skeleton is a run of `skeleton`, gathered in a list per
  // region as the walk meets its ops and laid out once the walk is done.
  std::vector<std::vector<Skeletal>> perRegion(1);
  // An op each region may still merge a later equal op into, a read or an
  // op of the region's parent, with where in the region's list the ops
  // after it start: none of them may change what a read reads, and nothing
  // changes what an op of the parent computes there.
  struct Mergeable {
    Operation *op;
    std::uint32_t since;
  };
  std::vector<std::vector<Mergeable>> mergeable(1);
  // The regions the walk is in, innermost last, and the first region of
  // each region op it is inside.
  std::vector<RegionId> open{body};
  std::vector<RegionId> firstRegions;

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
      std::vector<Skeletal> &list = perRegion[region.index()];
      std::vector<Mergeable> &earlier = mergeable[region.index()];
      Fate fate = Kept{};
      if ((entry == Entry::Reads || entry == Entry::OfParent) && !staysPut(op)) {
        auto unchanged = [&](const Mergeable &first) {
          if (entry == Entry::OfParent)
            return true;
          return llvm::none_of(llvm::ArrayRef(list).drop_front(first.since),
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
  std::vector<Operation *> ops;
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

llvm::SmallVector<Function::Pending> Function::rewrites() const {
  llvm::SmallVector<Pending> out;
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
