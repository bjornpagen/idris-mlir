// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tables of one function's e-graph: minting its ids, the hash-cons of
// its nodes, the making of a node with what it says of its value, the
// union-find over its classes, and the rebuild that pays the unions and
// restores congruence. No op is made here: a node of the input asks its
// own op, and a node a rule built reads its kind's tables; and a constant,
// whatever its kind, is a value, never an attribute.
#include "idr/Transforms/EGraph/Engine.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <cassert>

using namespace mlir;

namespace idr::egraph::detail {

//===----------------------------------------------------------------------===//
// Minting
//===----------------------------------------------------------------------===//

namespace {

// Whether a node enters the hash-cons. A leaf is the one node of its value,
// and an op with an identity is never another's equal, so neither is keyed.
bool keyed(const Node &node) {
  return match(
      node.what, [](const node::Input &op) { return op.identity == Identity::Shared; },
      [](const OneOf<node::Built, node::Held, node::Integer, node::Known> auto &) {
        return true;
      },
      [](const node::Leaf &) { return false; });
}

Identity identityOf(const Node &node) {
  return match(
      node.what, [](const node::Input &op) { return op.identity; },
      [](const OneOf<node::Built, node::Held, node::Integer, node::Known,
                     node::Leaf> auto &) { return Identity::Shared; });
}

} // namespace

// A node is made with a class of its own, which holds what it says and
// reaches where it can be computed; its operands, already its run of
// `children`, each become a use of the class they name, a root when the
// run was laid, which a union yet to be paid gives to its root with the
// rest of the class.
NodeId Function::make(Node node, Facts facts) {
  ++steps;
  NodeId made(static_cast<std::uint32_t>(nodes.size()));
  ClassId cls(static_cast<std::uint32_t>(classes.size()));
  assert(uses.size() == node.children.first &&
         children.size() == node.children.first + node.children.count &&
         "a node's operands are the last run laid");
  std::optional<RegionId> reach = needs(node);
  assert(reach && "a node is made only where its operands share a region");
  for (std::uint32_t place = node.children.first;
       place < node.children.first + node.children.count; ++place) {
    UseId use(place);
    uses.push_back({made, std::nullopt});
    Class &read = classes[children[place].index()];
    if (read.lastUse)
      uses[read.lastUse->index()].next = use;
    else
      read.firstUse = use;
    read.lastUse = use;
  }
  Identity identity = identityOf(node);
  Type type = node.type;
  nodes.push_back(std::move(node));
  classes.push_back(Class{type, std::move(facts), made, made, 1, std::nullopt, std::nullopt,
                          identity, *reach});
  forest.add(cls);
  nodeClass.push_back(cls);
  nextMember.push_back(std::nullopt);
  if (keyed(at(made)))
    remember(made);
  return made;
}

RegionId Function::newRegion(Region region) {
  regions.push_back(region);
  return RegionId(static_cast<std::uint32_t>(regions.size() - 1));
}

//===----------------------------------------------------------------------===//
// The hash-cons
//===----------------------------------------------------------------------===//

// A node's key: its kind, its type, its payload and its operands' classes.
// Two nodes of the input compare their properties through the op's own
// comparison; a node a rule built has its kind's default properties, and is
// equal only to another such of its kind; a constant an op holds is its
// attribute and the dialect that materializes it; an integer and any other
// constant the graph knows are their values.
bool Function::sameKey(const Node &a, std::span<const ClassId> ac, const Node &b,
                       std::span<const ClassId> bc) {
  if (a.type != b.type || !std::ranges::equal(ac, bc))
    return false;
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
            [](const OneOf<node::Built, node::Held, node::Integer, node::Known,
                           node::Leaf> auto &) { return false; });
      },
      [&](const node::Built &x) {
        return match(
            b.what, [&](const node::Built &y) { return x.kind == y.kind; },
            [](const OneOf<node::Input, node::Held, node::Integer, node::Known,
                           node::Leaf> auto &) { return false; });
      },
      [&](const node::Held &x) {
        return match(
            b.what,
            [&](const node::Held &y) { return x.value == y.value && x.dialect == y.dialect; },
            [](const OneOf<node::Input, node::Built, node::Integer, node::Known,
                           node::Leaf> auto &) { return false; });
      },
      [&](const node::Integer &x) {
        return match(
            b.what, [&](const node::Integer &y) { return x.value == y.value; },
            [](const OneOf<node::Input, node::Built, node::Held, node::Known,
                           node::Leaf> auto &) { return false; });
      },
      [&](const node::Known &x) {
        return match(
            b.what, [&](const node::Known &y) { return x.value == y.value; },
            [](const OneOf<node::Input, node::Built, node::Held, node::Integer,
                           node::Leaf> auto &) { return false; });
      },
      [](const node::Leaf &) { return false; });
}

std::uint32_t Function::hashOf(const Node &node) const {
  llvm::hash_code hash = match(
      node.what,
      [](const node::Input &op) {
        return llvm::hash_combine(op.origin->getName().getAsOpaquePointer(),
                                  op.origin->hashProperties());
      },
      [](const node::Built &op) { return llvm::hash_value(op.kind); },
      [](const node::Held &literal) {
        return llvm::hash_combine(literal.value.getAsOpaquePointer(), literal.dialect);
      },
      [](const node::Integer &integer) { return llvm::hash_value(integer.value); },
      [](const node::Known &known) { return hash_value(known.value); },
      [](const node::Leaf &) { return llvm::hash_code(0); });
  hash = llvm::hash_combine(hash, node.type.getAsOpaquePointer());
  for (ClassId operand : childrenOf(node))
    hash = llvm::hash_combine(hash, operand.index());
  return static_cast<std::uint32_t>(static_cast<std::size_t>(hash));
}

// The table is probed, never iterated for a result, so what an address
// adds to a hash moves only where a key sits, never what is found. Two
// keyed nodes may be equal while a rebuild has yet to unite their classes,
// and either stands for both.
std::optional<NodeId> Function::lookup(const Node &node) const {
  std::span<const ClassId> operands = childrenOf(node);
  std::uint32_t hash = hashOf(node);
  std::uint64_t mask = slots.size() - 1;
  for (std::uint64_t at = hash & mask;; at = (at + 1) & mask) {
    const Slot &slot = slots[at];
    if (!slot.node)
      return std::nullopt;
    const Node &there = this->at(*slot.node);
    if (slot.hash == hash && sameKey(node, operands, there, childrenOf(there)))
      return slot.node;
  }
}

void Function::remember(NodeId n) {
  if (2 * (std::uint64_t(filled) + 1) > slots.size()) {
    footprint::Vector<Slot> old = std::move(slots);
    assert(old.size() * 2 <= (std::uint64_t(1) << 32) && "a slot's hash places it in the table");
    slots.assign(old.size() * 2, Slot{});
    std::uint64_t mask = slots.size() - 1;
    for (const Slot &slot : old)
      if (slot.node) {
        std::uint64_t place = slot.hash & mask;
        while (slots[place].node)
          place = (place + 1) & mask;
        slots[place] = slot;
      }
  }
  std::uint32_t hash = hashOf(at(n));
  std::uint64_t mask = slots.size() - 1;
  std::uint64_t place = hash & mask;
  while (slots[place].node)
    place = (place + 1) & mask;
  slots[place] = {n, hash};
  ++filled;
}

// `n` is keyed under its operands as stored, which only a rebuild changes,
// and only once it has forgotten the key: so its slot is on the run its
// hash starts. The run after it shifts back over the hole, each key that
// may sit there, so no probe meets an empty slot before its key.
void Function::forget(NodeId n) {
  std::uint64_t mask = slots.size() - 1;
  std::uint64_t hole = hashOf(at(n)) & mask;
  while (slots[hole].node != n) {
    assert(slots[hole].node && "a keyed node is in the table");
    hole = (hole + 1) & mask;
  }
  for (std::uint64_t next = (hole + 1) & mask; slots[next].node; next = (next + 1) & mask) {
    std::uint64_t home = slots[next].hash & mask;
    // A key whose probe starts after the hole and no later than its slot
    // never passes the hole, so it stays.
    bool stays = hole < next ? hole < home && home <= next : hole < home || home <= next;
    if (stays)
      continue;
    slots[hole] = slots[next];
    hole = next;
  }
  slots[hole] = Slot{};
  --filled;
}

//===----------------------------------------------------------------------===//
// Nodes and classes
//===----------------------------------------------------------------------===//

namespace {

// Upstream's mark for a value it does not see as an integer: bounds of no
// width, which say nothing of one.
bool widthless(const ConstantIntRanges &range) { return range.umin().getBitWidth() == 0; }

// How `value` is written as an integer of `type`, where it is one. An
// interval of another width than the type's storage, as an op may state of
// a value it does not see as an integer, is no word of the type; a big's
// interval is of the integer it stands for, and an integer outside the
// small range is none the runtime holds in its word.
std::optional<IntegerForm> formOf(const APInt &value, Type type) {
  std::optional<IntegerForm> form = integerFormOf(type);
  if (!form)
    return std::nullopt;
  switch (*form) {
  case IntegerForm::Word:
  case IntegerForm::Splat:
    if (value.getBitWidth() != ConstantIntRanges::getStorageBitwidth(type))
      return std::nullopt;
    return form;
  case IntegerForm::Small: {
    std::optional<int64_t> small = value.trySExtValue();
    if (!small || *small < IDRIS_RT_SMALL_MIN || *small > IDRIS_RT_SMALL_MAX)
      return std::nullopt;
    return form;
  }
  }
  return std::nullopt;
}

} // namespace

ClassId Function::leaf(Value value, RegionId home) {
  Node node{node::Leaf{value, home}, value.getType(), childrenFor({})};
  return classOfNode(make(std::move(node), Facts()));
}

// Two ops holding one attribute are one constant, which says what each
// says: the interval the op gives it, and the value read once from its
// attribute (an integer's interval where the op gives none).
ClassId Function::held(Attribute value, Type type, Dialect *dialect,
                       std::optional<ConstantIntRanges> interval) {
  Node node{node::Held{value, dialect}, type, childrenFor({})};
  if (std::optional<NodeId> found = lookup(node))
    return forest.find(classOfNode(*found));
  Facts facts = heldFacts(value);
  (void)facts.meet({interval, std::nullopt});
  ClassId cls = classOfNode(make(std::move(node), std::move(facts)));
  joinConstant(cls);
  return cls;
}

std::optional<IntegerForm> integerFormOf(Type type) {
  if (type.isIntOrIndex())
    return IntegerForm::Word;
  auto shaped = dyn_cast<ShapedType>(type);
  if (shaped && shaped.hasStaticShape() && shaped.getElementType().isIntOrIndex())
    return IntegerForm::Splat;
  if (isCarriedAsBig(type) && usesOf(type) == Uses::Many)
    return IntegerForm::Small;
  return std::nullopt;
}

// Two integers of one value and type are one node.
std::optional<ClassId> Function::integer(const APInt &value, Type type) {
  std::optional<IntegerForm> form = formOf(value, type);
  if (!form)
    return std::nullopt;
  Node node{node::Integer{value, *form}, type, childrenFor({})};
  if (std::optional<NodeId> found = lookup(node))
    return forest.find(classOfNode(*found));
  if (nodes.size() >= budget)
    return std::nullopt;
  return classOfNode(make(std::move(node), {ConstantIntRanges::constant(value), std::nullopt}));
}

// Two constants of one value and type are one node, which says what the
// constant does of its value: a big past the small range, its sign's
// interval too.
std::optional<ClassId> Function::known(const Constant &value, Type type) {
  assert(placedAt(value, type) && "a constant has a node only where its constant op stands");
  Node node{node::Known{value}, type, childrenFor({})};
  if (std::optional<NodeId> found = lookup(node))
    return forest.find(classOfNode(*found));
  if (nodes.size() >= budget)
    return std::nullopt;
  return classOfNode(make(std::move(node), detail::factsOf(value)));
}

bool Function::placeable(const Facts &facts, Type type) const {
  if (std::optional<APInt> value = facts.integer(); value && formOf(*value, type))
    return true;
  return facts.constant && placedAt(*facts.constant, type);
}

// A node's own run of operands is given back before a constant is made,
// since a node is made over the last run laid.
std::optional<ClassId> Function::constantOf(const Facts &facts, Type type) {
  if (std::optional<APInt> value = facts.integer(); value && formOf(*value, type))
    return integer(*value, type);
  if (facts.constant && placedAt(*facts.constant, type))
    return known(*facts.constant, type);
  return std::nullopt;
}

Changed Facts::meet(const Facts &other) {
  Changed changed = Changed::No;
  if (!constant && other.constant) {
    constant = other.constant;
    changed = Changed::Yes;
  }
  if (!other.range || widthless(*other.range))
    return changed;
  if (!range || widthless(*range)) {
    range = *other.range;
    return Changed::Yes;
  }
  assert(range->umin().getBitWidth() == other.range->umin().getBitWidth() &&
         "two intervals of one value are of its type's width");
  ConstantIntRanges met = range->intersection(*other.range);
  // Each interval holds of the one value, so their meet holds it: an empty
  // meet is a fact that was wrong.
  assert(met.umin().ule(met.umax()) && met.smin().sle(met.smax()) &&
         "the members of a class disagree on its value");
  if (met == *range)
    return changed;
  range = met;
  return Changed::Yes;
}

// A value that is one of two: each interval holds of it on its own path,
// so their union holds of it; a constant only where both are that one.
// Two intervals of other widths are of values of two types, as a region's
// edges may pass, and say nothing of one width.
Facts Facts::joined(const Facts &other) const {
  Facts out;
  if (range && other.range && !widthless(*range) && !widthless(*other.range) &&
      range->umin().getBitWidth() == other.range->umin().getBitWidth())
    out.range = range->rangeUnion(*other.range);
  if (constant && other.constant && *constant == *other.constant)
    out.constant = constant;
  return out;
}

// The interval upstream's transfer function gives `op` over its operands'
// intervals as their roots now hold them, an operand with none its value's
// whole range.
std::optional<ConstantIntRanges> Function::intervalOf(Operation *op,
                                                      std::span<const ClassId> operands) const {
  auto ranges = dyn_cast<InferIntRangeInterface>(op);
  if (!ranges)
    return std::nullopt;
  SmallVector<IntegerValueRange, 4> inputs;
  for (auto [operand, value] : llvm::zip_equal(operands, op->getOperands())) {
    const Facts &input = factsOf(operand);
    inputs.push_back(input.range ? IntegerValueRange(*input.range)
                                 : IntegerValueRange::getMaxRange(value));
  }
  std::optional<ConstantIntRanges> interval;
  ranges.inferResultRangesFromOptional(inputs, [&](Value, const IntegerValueRange &result) {
    if (!result.isUninitialized())
      interval = result.getValue();
  });
  return interval;
}

// A node's meaning is computed only over constants: the op of the input's,
// read with its own properties, or the kind's a rule built. What it
// computes takes the runtime's memory for a string or a big past the small
// range, within the bytes the function's constants may take; past them the
// constant is not kept, and the op that computes it stays.
std::optional<Facts> Function::meant(const What &what, Type type,
                                     std::span<const ClassId> operands) {
  SmallVector<const Class *, 4> constants;
  for (ClassId operand : operands) {
    const Class &cls = at(forest.rootOf(operand));
    if (!cls.facts.isConstant())
      return std::nullopt;
    constants.push_back(&cls);
  }
  std::optional<Facts> facts = match(
      what,
      [&](const node::Input &op) -> std::optional<Facts> {
        return op.meaning ? (*op.meaning)(*this, op.origin, type, constants) : std::nullopt;
      },
      [&](const node::Built &op) -> std::optional<Facts> {
        const std::optional<MeaningOfBuilt> &meaning = kinds.built[op.kind];
        return meaning ? (*meaning)(type, constants) : std::nullopt;
      },
      []<Atom N>(const N &) -> std::optional<Facts> { return std::nullopt; });
  if (!facts)
    return std::nullopt;
  ++steps;
  if (facts->constant) {
    std::uint64_t bytes = bytesOf(*facts->constant);
    if (bytes > constantBytes - computedBytes)
      facts->constant.reset();
    else
      computedBytes += bytes;
  }
  return facts;
}

// An atom reads no class: what it says it said when it was made, which its
// class already holds.
Facts Function::saysOf(NodeId n) {
  const Node &node = at(n);
  Facts said = match(
      node.what,
      [&](const node::Input &op) -> Facts {
        return {intervalOf(op.origin, childrenOf(node)), std::nullopt};
      },
      [&](const node::Built &op) -> Facts {
        return {intervalOf(op, node.type, childrenOf(node)), std::nullopt};
      },
      []<Atom N>(const N &) { return Facts(); });
  if (std::optional<Facts> computed = meant(node.what, node.type, childrenOf(node)))
    (void)said.meet(*computed);
  return said;
}

Run Function::childrenFor(std::span<const ClassId> operands) {
  Run run{static_cast<std::uint32_t>(children.size()), static_cast<std::uint32_t>(operands.size())};
  for (ClassId operand : operands)
    children.push_back(forest.find(operand));
  return run;
}

// Shrunk, never grown, so a class id needs no default to fill it.
void Function::unlay(Run run) {
  assert(run.first + run.count == children.size() && "only the last run laid is given back");
  children.erase(children.begin() + static_cast<std::ptrdiff_t>(run.first), children.end());
}

// A class holding a fresh identity is never one with a constant, which a
// second equal identity could then never join: an op that makes one is its
// constant only where it enters the graph with a meaning that computes it
// (insert). The facts are read before a node is made, which moves them.
void Function::joinConstant(ClassId c) {
  ClassId root = forest.find(c);
  if (at(root).identity == Identity::Own)
    return;
  Facts facts = at(root).facts;
  if (std::optional<ClassId> is = constantOf(facts, at(root).type))
    (void)unite(root, *is);
}

// The class of a floating op of the input over `operands`: an equal node's
// class, found in the hash-cons; or the constant its meaning computes, or,
// for a call, the constant its callee returns, with no node of its own, as
// a node a rule built over constants is, where the type places it; or a new
// node in a class of its own, with its interval and what its meaning
// computes, united with the constant it is where its facts are one, and
// with an argument where its callee gives that back. An op that makes a
// fresh identity, as one that computes a string or a big does, becomes its
// constant only here. The rules run in the rounds after the walk.
ClassId Function::insert(node::Input op, Type type, std::span<const ClassId> operands) {
  if (op.identity == Identity::Shared) {
    Node probe{op, type, childrenFor(operands)};
    std::optional<NodeId> found = lookup(probe);
    unlay(probe.children);
    if (found)
      return forest.find(classOfNode(*found));
  }
  // An op whose fold gives the value of one of its operands, or of an
  // operand of the op that built one, is that value's class, with no node
  // of its own.
  if (op.given) {
    SmallVector<const Class *, 4> roots;
    for (ClassId operand : operands)
      roots.push_back(&at(forest.rootOf(operand)));
    if (std::optional<ClassId> given = (*op.given)(*this, op.origin, roots);
        given && at(forest.rootOf(*given)).type == type)
      return forest.find(*given);
  }
  // A call's callee, resolved once here, whose facts are read by its id.
  std::optional<solver::FunctionId> callee;
  if (auto call = dyn_cast<CallOp>(op.origin); call && callees) {
    callee = callees->calleeOf(call);
    if (callee)
      if (std::optional<ClassId> constant = returnedBy(*callee, call, 0))
        return *constant;
  }
  std::optional<Facts> computed = meant(op, type, operands);
  if (computed && placeable(*computed, type))
    if (std::optional<ClassId> is = constantOf(*computed, type))
      return *is;
  Facts facts{intervalOf(op.origin, operands), std::nullopt};
  if (computed)
    (void)facts.meet(*computed);
  ClassId cls = classOfNode(make(Node{op, type, childrenFor(operands)}, std::move(facts)));
  joinConstant(cls);
  if (callee)
    if (std::optional<ClassId> given = giveBack(*callee, operands, type))
      (void)unite(cls, *given);
  return cls;
}

// The class of a node a right side built over `operands`: an equal node's
// class, the constant it is, or a new node in a class of its own with what
// its kind's tables give. None once the function's budget of nodes is
// spent: the rule then does not apply, and the function is less optimized.
std::optional<ClassId> Function::insert(node::Built op, Type type,
                                        std::span<const ClassId> operands) {
  Node node{op, type, childrenFor(operands)};
  if (std::optional<NodeId> found = lookup(node)) {
    unlay(node.children);
    return forest.find(classOfNode(*found));
  }
  if (nodes.size() >= budget) {
    unlay(node.children);
    return std::nullopt;
  }
  // A side whose operands share no region where each can be computed, as
  // one may whose match went through a member of an inner region in a class
  // of an outer reach, is computed nowhere: the rule does not apply.
  if (!needs(node)) {
    unlay(node.children);
    return std::nullopt;
  }
  // One built over constants is the constant it computes at once, as a fold
  // made it, and no node of its own: the budget, not yet spent, makes the
  // constant.
  Facts facts{intervalOf(op, type, childrenOf(node)), std::nullopt};
  if (std::optional<Facts> computed = meant(op, type, childrenOf(node)))
    (void)facts.meet(*computed);
  if (placeable(facts, type)) {
    unlay(node.children);
    return constantOf(facts, type);
  }
  return classOfNode(make(std::move(node), std::move(facts)));
}

// A floating call of a function that gives back one of its arguments whole,
// as the optimizer decided, is that argument: the call floats only where
// its row carries neither crash nor divergence, so nothing is lost with it.
std::optional<ClassId> Function::giveBack(solver::FunctionId callee,
                                          std::span<const ClassId> operands, Type type) {
  for (const identities::GivesBack &fact : callees->of(callee).givesBack)
    if (fact.result.index == 0 && fact.result.fields.empty() && fact.argument.fields.empty() &&
        at(operands[fact.argument.index]).type == type)
      return operands[fact.argument.index];
  return std::nullopt;
}

// The constant a final callee's body returns is the same at every call of
// it, so it is a fact of the call's result, read as the attribute its
// constant op holds; where the call's index arguments make its result's
// type another than the callee's own, that constant is no value of it.
std::optional<ClassId> Function::returnedBy(solver::FunctionId callee, CallOp call,
                                            unsigned result) {
  llvm::ArrayRef<std::optional<ReturnedConstant>> returned = callees->returns(callee);
  if (result >= returned.size() || !returned[result])
    return std::nullopt;
  const ReturnedConstant &constant = *returned[result];
  Type type = call->getResult(result).getType();
  if (constant.type != type || nodes.size() >= budget)
    return std::nullopt;
  return held(constant.value, type, constant.dialect, std::nullopt);
}

//===----------------------------------------------------------------------===//
// The union-find
//===----------------------------------------------------------------------===//

// The two classes as one, linked at once and paid by the rebuild, reaching
// the outer of their reaches. The root is the class holding an identity,
// so that class stays its own; else the larger, so paths stay short; else
// the older. Two classes stay apart where they are two values, or one
// value nothing computes at all their uses: both holding identities (a
// rule may show two cells' contents equal, never that two allocations are
// one), or reaching regions neither of which holds the other.
Changed Function::unite(ClassId a, ClassId b) {
  ClassId x = forest.find(a), y = forest.find(b);
  if (x == y)
    return Changed::No;
  assert(at(x).type == at(y).type && "only values of one type are one value");
  if (at(x).identity == Identity::Own && at(y).identity == Identity::Own)
    return Changed::No;
  std::optional<RegionId> reach = outerOf(at(x).reach, at(y).reach);
  if (!reach)
    return Changed::No;
  auto before = [&](ClassId p, ClassId q) {
    const Class &l = at(p), &r = at(q);
    if (l.identity != r.identity)
      return l.identity == Identity::Own;
    if (l.size != r.size)
      return l.size > r.size;
    return p < q;
  };
  if (before(y, x))
    std::swap(x, y);
  forest.link(y, x);
  at(x).size += at(y).size;
  at(x).reach = *reach;
  if (at(y).identity == Identity::Own)
    at(x).identity = Identity::Own;
  owed.push_back({x, y});
  ++unions;
  return Changed::Yes;
}

// `from`'s members, users and facts given to `into`: its lists joined at
// the end of `into`'s, its facts met with `into`'s.
ClassId Function::pay(const Owed &debt) {
  Class &from = at(debt.from);
  Class &into = at(debt.into);
  nextMember[into.last.index()] = from.first;
  into.last = from.last;
  if (from.firstUse) {
    if (into.lastUse)
      uses[into.lastUse->index()].next = from.firstUse;
    else
      into.firstUse = from.firstUse;
    into.lastUse = from.lastUse;
  }
  (void)into.facts.meet(from.facts);
  return debt.into;
}

// Each class whose members grew, or whose facts or reach the last round's
// rebuild moved, is repaired; a repair's unions are paid and their roots
// repaired in turn, a chunk at a time, each chunk its classes' roots once,
// until none is owed. A repair unites only congruent nodes or a class with
// its constant, so each chunk after the first follows a union, which leaves
// one class fewer: the rebuild ends.
void Function::rebuild() {
  footprint::Vector<ClassId> work = std::exchange(carried, {});
  for (;;) {
    for (const Owed &debt : std::exchange(owed, {}))
      work.push_back(pay(debt));
    if (work.empty())
      break;
    footprint::Vector<ClassId> chunk = std::exchange(work, {});
    for (ClassId &c : chunk)
      c = forest.find(c);
    llvm::sort(chunk);
    chunk.erase(std::unique(chunk.begin(), chunk.end()), chunk.end());
    for (ClassId c : chunk)
      repair(c);
  }
  llvm::sort(carried);
  carried.erase(std::unique(carried.begin(), carried.end()), carried.end());
}

// Each node that reads `c` keyed again by its operands' roots: one now equal
// to a keyed node unites with it. Then what it says over its operands'
// facts as they are now narrows its class, where the class does not know
// its constant already, which nothing narrows; and where it can be computed
// widens its class's reach; a class so changed has its own users read
// again at the next round's rebuild, so a change climbs one class a round
// and no rebuild waits on a chain of them.
void Function::repair(ClassId c) {
  joinConstant(c);
  for (std::optional<UseId> use = at(c).firstUse; use; use = uses[use->index()].next) {
    ++steps;
    NodeId user = uses[use->index()].user;
    Run run = at(user).children;
    auto toRoots = [&] {
      for (std::uint32_t place = run.first; place < run.first + run.count; ++place)
        children[place] = forest.find(children[place]);
    };
    // An op with an identity is keyed by nothing, so only its operands move.
    if (keyed(at(user))) {
      forget(user);
      toRoots();
      if (std::optional<NodeId> equal = lookup(at(user)))
        (void)unite(classOfNode(user), classOfNode(*equal));
      remember(user);
    } else {
      toRoots();
    }
    ClassId holder = forest.find(classOfNode(user));
    Changed narrowed = Changed::No;
    if (!at(holder).facts.isConstant()) {
      Facts said = saysOf(user);
      narrowed = at(holder).facts.meet(said);
    }
    if ((narrowed | widen(holder, at(user))) == Changed::Yes)
      carried.push_back(holder);
  }
}

// A member's region moves only outward as its operands' reaches do, which
// all held its last region, so it and its class's reach still nest.
Changed Function::widen(ClassId holder, const Node &member) {
  std::optional<RegionId> now = needs(member);
  assert(now && "a node's operands' reaches nest as they move outward");
  std::optional<RegionId> reach = outerOf(at(holder).reach, *now);
  assert(reach && "a member's region nests in its class's reach");
  if (*reach == at(holder).reach)
    return Changed::No;
  at(holder).reach = *reach;
  return Changed::Yes;
}

// The reaches the last rebuild moved spread to their fixpoint, each moving
// only outward, at most its depth: so every class's reach is the outermost
// region one of its members can be computed in. Then every id is read at
// its root.
void Function::settle() {
  footprint::Vector<ClassId> moved = std::exchange(carried, {});
  while (!moved.empty()) {
    ClassId c = forest.find(moved.back());
    moved.pop_back();
    for (std::optional<UseId> use = at(c).firstUse; use; use = uses[use->index()].next) {
      ++steps;
      NodeId user = uses[use->index()].user;
      ClassId holder = forest.find(classOfNode(user));
      if (widen(holder, at(user)) == Changed::Yes)
        moved.push_back(holder);
    }
  }
  for (ValueId value : numbering.size().ids())
    if (std::optional<ClassId> &cls = classOf[value])
      cls = forest.find(*cls);
  for (ClassId &cls : nodeClass)
    cls = forest.find(cls);
  for (ClassId operand : children)
    assert(forest.isRoot(operand) && "a rebuild leaves every operand at its root");
}

} // namespace idr::egraph::detail
