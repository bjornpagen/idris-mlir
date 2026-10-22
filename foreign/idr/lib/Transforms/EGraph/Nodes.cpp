// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tables of one function's e-graph: minting its ids, the hash-cons of
// its floating nodes, and the making of a node, with its analyses and the
// rules rooted at its kind run at once, and of the class it lands in,
// which keeps what the node knows.
#include "idr/Transforms/EGraph/Engine.h"

#include "mlir/IR/Block.h"
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

// A node of the input stands for its op. A node a rule built has none: it
// stands for the op the write-back would make of it, of its name, its type
// and the op's default properties, made here detached over stand-ins for
// its operands, one per class, so that a fold comparing two operands finds
// them equal exactly where their classes are; it is destroyed once read,
// so it never enters the function's tables.
Facts Function::analyse(const Node &node) {
  const auto &op = std::get<node::Op>(node.what);
  std::span<const ClassId> operands = childrenOf(node);
  if (op.origin)
    return factsOf(op.origin, operands);
  Block standIns;
  SmallVector<Value, 4> values;
  for (auto [i, operand] : llvm::enumerate(operands)) {
    std::span<const ClassId> before = operands.first(i);
    auto seen = std::ranges::find(before, operand);
    values.push_back(seen != before.end()
                         ? values[static_cast<std::size_t>(seen - before.begin())]
                         : Value(standIns.addArgument(at(operand).type, fn.getLoc())));
  }
  OperationState state(fn.getLoc(), op.name);
  state.addOperands(values);
  state.addTypes(node.type);
  Operation *made = Operation::create(state);
  Facts facts = factsOf(made, operands);
  made->destroy();
  return facts;
}

// The class of a floating op over `operands`: an equal node's class, found
// in the hash-cons; or a new node, its analyses computed and the rules
// rooted at its kind run on it, in the class those decide: a constant's
// when it folds, an argument's when its callee gives that back, a right
// side's when a rule matches, else a class of its own. A class that
// replaces the node is the same value, so it meets what the node knew. None
// once the function's budget of nodes is spent, for a node a rule asked
// for: the form is then kept as it was, less optimized.
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
  Facts facts = analyse(at(made));

  auto replacedBy = [&](ClassId cls) {
    at(cls).facts.meet(facts);
    return cls;
  };
  auto decided = [&]() -> ClassId {
    if (facts.constant)
      return replacedBy(constant(facts.constant, type, name.getDialect()));
    if (std::optional<ClassId> given =
            giveBack(std::get<node::Op>(at(made).what), operands, type))
      return replacedBy(*given);
    if (rules == Rules::Run)
      if (std::optional<ClassId> by = rewrite(made))
        return replacedBy(*by);
    Class own{Run{static_cast<std::uint32_t>(members.size()), 1}, type, facts};
    members.push_back(made);
    return newClass(std::move(own));
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

} // namespace idr::egraph::detail
