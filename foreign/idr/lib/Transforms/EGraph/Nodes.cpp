// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tables of one function's e-graph: minting its ids, the hash-cons of
// its floating nodes, and the making of a node, with its analyses and the
// rules rooted at its kind run at once, and of the class it lands in,
// which keeps what the node knows. No op is made here: a node of the input
// asks its own op, and a node a rule built reads its kind's tables.
#include "idr/Transforms/EGraph/Engine.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::egraph::detail {

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

//===----------------------------------------------------------------------===//
// The hash-cons
//===----------------------------------------------------------------------===//

// A node's key: its op, its type, its properties and its operands' classes.
// Two nodes of the input compare their properties through the op's own
// comparison; a node a rule built has its kind's default properties, and is
// equal only to another such of its kind. A node with an identity has no
// key, and neither has an atom, which enters no table.
bool Function::sameKey(const Node &a, std::span<const ClassId> ac, const Node &b,
                       std::span<const ClassId> bc) {
  if (a.type != b.type || !std::ranges::equal(ac, bc))
    return false;
  auto never = []<Atom N>(const N &) { return false; };
  return match(
      a.what,
      [&](const node::Input &x) {
        return match(
            b.what,
            [&](const node::Input &y) {
              Operation *p = x.origin, *q = y.origin;
              return x.identity == Identity::Shared && y.identity == Identity::Shared &&
                     p->getName() == q->getName() &&
                     p->getRawDictionaryAttrs() == q->getRawDictionaryAttrs() &&
                     p->getName().compareOpProperties(p->getPropertiesStorage(),
                                                      q->getPropertiesStorage());
            },
            [](const node::Built &) { return false; }, never);
      },
      [&](const node::Built &x) {
        return match(
            b.what, [&](const node::Built &y) { return x.kind == y.kind; },
            [](const node::Input &) { return false; }, never);
      },
      never);
}

std::uint64_t Function::hashOf(const Node &node, std::span<const ClassId> operands) const {
  llvm::hash_code hash = match(
      node.what,
      [](const node::Input &op) {
        return llvm::hash_combine(op.origin->getName().getAsOpaquePointer(),
                                  op.origin->hashProperties());
      },
      [](const node::Built &op) { return llvm::hash_value(op.kind); },
      []<Atom N>(const N &) { return llvm::hash_code(0); });
  hash = llvm::hash_combine(hash, node.type.getAsOpaquePointer());
  for (ClassId operand : operands)
    hash = llvm::hash_combine(hash, operand.index());
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
    footprint::Vector<Slot> old = std::move(slots);
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
  ClassId cls = newClass({{}, value.getType(), {}});
  alone({node::Leaf{value}, value.getType(), {}}, cls);
  if (Attribute known; matchPattern(value, m_Constant(&known)))
    at(cls).facts.constant = known;
  return cls;
}

ClassId Function::constant(Attribute value, Type type, Dialect *dialect) {
  ClassId cls = newClass({{}, type, {value, std::nullopt}});
  alone({node::Constant{value, dialect}, type, {}}, cls);
  if (auto integer = dyn_cast<IntegerAttr>(value))
    at(cls).facts.range = ConstantIntRanges::constant(integer.getValue());
  return cls;
}

void Facts::meet(const Facts &other) {
  if (!constant)
    constant = other.constant;
  if (other.range)
    range = range ? range->intersection(*other.range) : *other.range;
}

// What `op` computes over its operands' classes: the constant its fold
// gives when every operand's class holds a constant, so that a fold which
// moves operands in place moves none; and the interval upstream's transfer
// function gives their intervals, an operand with none its value's whole
// range.
Facts Function::factsOf(Operation *op, std::span<const ClassId> operands) const {
  Facts facts;
  SmallVector<Attribute, 4> constants;
  for (ClassId operand : operands)
    constants.push_back(at(operand).facts.constant);
  if (llvm::all_of(constants, [](Attribute a) { return static_cast<bool>(a); })) {
    SmallVector<OpFoldResult, 1> folded;
    if (succeeded(op->fold(constants, folded)) && folded.size() == 1)
      if (auto attr = dyn_cast_if_present<Attribute>(folded.front()))
        facts.constant = attr;
  }
  if (auto ranges = dyn_cast<InferIntRangeInterface>(op)) {
    SmallVector<IntegerValueRange, 4> inputs;
    for (auto [operand, value] : llvm::zip_equal(operands, op->getOperands())) {
      const Facts &input = at(operand).facts;
      inputs.push_back(input.range ? IntegerValueRange(*input.range)
                                   : IntegerValueRange::getMaxRange(value));
    }
    ranges.inferResultRangesFromOptional(inputs, [&](Value, const IntegerValueRange &result) {
      if (!result.isUninitialized())
        facts.range = result.getValue();
    });
  }
  return facts;
}

Run Function::childrenFor(std::span<const ClassId> operands) {
  Run run{static_cast<std::uint32_t>(children.size()), static_cast<std::uint32_t>(operands.size())};
  children.insert(children.end(), operands.begin(), operands.end());
  return run;
}

ClassId Function::ownClass(NodeId made, Type type, Facts facts) {
  Class own{Run{static_cast<std::uint32_t>(members.size()), 1}, type, std::move(facts)};
  members.push_back(made);
  return newClass(std::move(own));
}

// The class of a floating op of the input over `operands`: an equal node's
// class, found in the hash-cons; or a new node, its analyses computed and
// the rules rooted at its kind run on it, in the class those decide: a
// constant's when it folds, an argument's when its callee gives that back,
// a right side's when a rule matches, else a class of its own. A class that
// replaces the node is the same value, so it meets what the node knew.
ClassId Function::insert(node::Input op, Type type, std::span<const ClassId> operands) {
  Node node{op, type, childrenFor(operands)};
  if (op.identity == Identity::Shared)
    if (std::optional<ClassId> found = lookup(node)) {
      children.resize(node.children.first);
      return *found;
    }
  NodeId made = newNode(std::move(node));
  Facts facts = factsOf(op.origin, operands);

  auto replacedBy = [&](ClassId cls) {
    at(cls).facts.meet(facts);
    return cls;
  };
  auto decided = [&]() -> ClassId {
    if (facts.constant)
      return replacedBy(constant(facts.constant, type, op.origin->getDialect()));
    if (std::optional<ClassId> given = giveBack(op, operands, type))
      return replacedBy(*given);
    if (std::optional<ClassId> by = rewrite(made, op, type))
      return replacedBy(*by);
    return ownClass(made, type, facts);
  };
  ClassId cls = decided();
  if (op.identity == Identity::Shared)
    remember(made, cls);
  return cls;
}

// The class of a node a right side built over `operands`: an equal node's
// class, or a new node in a class of its own with what its kind's tables
// give, its insertion running no rules. None once the function's budget of
// nodes is spent: the input's form is then kept as it was, less optimized.
std::optional<ClassId> Function::insert(node::Built op, Type type,
                                        std::span<const ClassId> operands) {
  Node node{op, type, childrenFor(operands)};
  if (std::optional<ClassId> found = lookup(node)) {
    children.resize(node.children.first);
    return found;
  }
  if (nodes.size() >= budget) {
    children.resize(node.children.first);
    return std::nullopt;
  }
  NodeId made = newNode(std::move(node));
  ClassId cls = ownClass(made, type, factsOf(op, type, operands));
  remember(made, cls);
  return cls;
}

// A floating call of a function that gives back one of its arguments whole,
// as the optimizer decided, is that argument: the call floats only where
// its row carries neither crash nor divergence, so nothing is lost with it.
std::optional<ClassId> Function::giveBack(const node::Input &op,
                                          std::span<const ClassId> operands, Type type) {
  if (!callees)
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

} // namespace idr::egraph::detail
