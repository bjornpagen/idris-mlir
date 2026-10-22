// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tables of one function's e-graph: minting its ids, the hash-cons of
// its nodes, the making of a node with what it says of its value, the
// union-find over its classes, and the rebuild that pays the unions and
// restores congruence. No op is made here: a node of the input asks its
// own op, and a node a rule built reads its kind's tables; and an integer
// is a value, never an attribute.
#include "idr/Transforms/EGraph/Engine.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Matchers.h"
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
      [](const OneOf<node::Built, node::Constant, node::Integer> auto &) { return true; },
      [](const node::Leaf &) { return false; });
}

Identity identityOf(const Node &node) {
  return match(
      node.what, [](const node::Input &op) { return op.identity; },
      [](const OneOf<node::Built, node::Constant, node::Integer, node::Leaf> auto &) {
        return Identity::Shared;
      });
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
// equal only to another such of its kind; an integer is its value, and a
// constant its attribute and the dialect that materializes it.
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
            [](const OneOf<node::Built, node::Constant, node::Integer, node::Leaf> auto &) {
              return false;
            });
      },
      [&](const node::Built &x) {
        return match(
            b.what, [&](const node::Built &y) { return x.kind == y.kind; },
            [](const OneOf<node::Input, node::Constant, node::Integer, node::Leaf> auto &) {
              return false;
            });
      },
      [&](const node::Integer &x) {
        return match(
            b.what, [&](const node::Integer &y) { return x.value == y.value; },
            [](const OneOf<node::Input, node::Built, node::Constant, node::Leaf> auto &) {
              return false;
            });
      },
      [&](const node::Constant &x) {
        return match(
            b.what,
            [&](const node::Constant &y) { return x.value == y.value && x.dialect == y.dialect; },
            [](const OneOf<node::Input, node::Built, node::Integer, node::Leaf> auto &) {
              return false;
            });
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
      [](const node::Integer &integer) { return llvm::hash_value(integer.value); },
      [](const node::Constant &literal) {
        return llvm::hash_combine(literal.value.getAsOpaquePointer(), literal.dialect);
      },
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

// A constant an op holds is that attribute, and lies in the interval the
// op gives it, or, where the op gives none, is the one value of an integer
// attribute.
Facts held(Attribute value, std::optional<ConstantIntRanges> interval) {
  if (!interval)
    if (auto integer = dyn_cast<IntegerAttr>(value))
      interval = ConstantIntRanges::constant(integer.getValue());
  return {interval, value};
}

// Upstream's mark for a value it does not see as an integer: bounds of no
// width, which say nothing of one.
bool widthless(const ConstantIntRanges &range) { return range.umin().getBitWidth() == 0; }

// How `value` is written as a word of `type`, where it is one. An interval
// of another width than the type's storage, as an op may state of a value
// it does not see as an integer, is no word of the type.
std::optional<IntegerForm> wordOf(const APInt &value, Type type) {
  std::optional<IntegerForm> form = integerFormOf(type);
  if (!form || value.getBitWidth() != ConstantIntRanges::getStorageBitwidth(type))
    return std::nullopt;
  return form;
}

} // namespace

ClassId Function::leaf(Value value, RegionId home) {
  Facts facts;
  if (Attribute known; matchPattern(value, m_Constant(&known)))
    facts = held(known, std::nullopt);
  Node node{node::Leaf{value, home}, value.getType(), childrenFor({})};
  return classOfNode(make(std::move(node), std::move(facts)));
}

// Two ops holding one attribute are one constant, which says what each
// says.
ClassId Function::constant(Attribute value, Type type, Dialect *dialect,
                           std::optional<ConstantIntRanges> interval) {
  Node node{node::Constant{value, dialect}, type, childrenFor({})};
  if (std::optional<NodeId> found = lookup(node))
    return forest.find(classOfNode(*found));
  ClassId cls = classOfNode(make(std::move(node), held(value, interval)));
  joinInteger(cls);
  return cls;
}

std::optional<IntegerForm> integerFormOf(Type type) {
  if (type.isIntOrIndex())
    return IntegerForm::Word;
  auto shaped = dyn_cast<ShapedType>(type);
  if (shaped && shaped.hasStaticShape() && shaped.getElementType().isIntOrIndex())
    return IntegerForm::Splat;
  return std::nullopt;
}

// Two integers of one value and type are one node.
std::optional<ClassId> Function::integer(const APInt &value, Type type) {
  std::optional<IntegerForm> form = wordOf(value, type);
  if (!form)
    return std::nullopt;
  Node node{node::Integer{value, *form}, type, childrenFor({})};
  if (std::optional<NodeId> found = lookup(node))
    return forest.find(classOfNode(*found));
  if (nodes.size() >= budget)
    return std::nullopt;
  return classOfNode(make(std::move(node), {ConstantIntRanges::constant(value), Attribute()}));
}

Changed Facts::meet(const Facts &other) {
  Changed changed = Changed::No;
  if (!attribute && other.attribute) {
    attribute = other.attribute;
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

// An atom reads no class: what it says it said when it was made, which its
// class already holds.
Facts Function::saysOf(NodeId n) const {
  const Node &node = at(n);
  return match(
      node.what,
      [&](const node::Input &op) -> Facts {
        return {intervalOf(op.origin, childrenOf(node)), Attribute()};
      },
      [&](const node::Built &op) { return saysOf(op, node.type, childrenOf(node)); },
      []<Atom N>(const N &) { return Facts(); });
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

void Function::joinInteger(ClassId c) {
  ClassId root = forest.find(c);
  if (std::optional<APInt> value = at(root).facts.integer())
    if (std::optional<ClassId> is = integer(*value, at(root).type))
      (void)unite(root, *is);
}

// The class of a floating op of the input over `operands`: an equal node's
// class, found in the hash-cons; or a new node in a class of its own, with
// its interval, united with the integer it is where its interval is one
// value, and with an argument where its callee gives that back. The rules
// run in the rounds after the walk.
ClassId Function::insert(node::Input op, Type type, std::span<const ClassId> operands) {
  Node node{op, type, childrenFor(operands)};
  if (op.identity == Identity::Shared)
    if (std::optional<NodeId> found = lookup(node)) {
      unlay(node.children);
      return forest.find(classOfNode(*found));
    }
  // What the op computes is its interval alone. Its own fold is never
  // asked: a fold makes the attribute of what it computes, and the graph
  // makes none, so a constant that is no integer (a string, a Double, a big
  // past the small range, a data constant) is known only where an op of the
  // input holds it, and the write-back makes what it writes.
  Facts facts{intervalOf(op.origin, childrenOf(node)), Attribute()};
  ClassId cls = classOfNode(make(std::move(node), std::move(facts)));
  joinInteger(cls);
  if (std::optional<ClassId> given = giveBack(op, operands, type))
    (void)unite(cls, *given);
  return cls;
}

// The class of a node a right side built over `operands`: an equal node's
// class, the integer it is, or a new node in a class of its own with what
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
  // One built over constants is its integer at once, as a fold made it,
  // and no node of its own: the budget, not yet spent, makes the integer.
  Facts facts = saysOf(op, type, childrenOf(node));
  if (std::optional<APInt> value = facts.integer(); value && wordOf(*value, type)) {
    unlay(node.children);
    return integer(*value, type);
  }
  return classOfNode(make(std::move(node), std::move(facts)));
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
// its integer, so each chunk after the first follows a union, which leaves
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
// facts as they are now narrows its class, and where it can be computed
// widens its class's reach; a class so changed has its own users read
// again at the next round's rebuild, so a change climbs one class a round
// and no rebuild waits on a chain of them.
void Function::repair(ClassId c) {
  joinInteger(c);
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
    if ((at(holder).facts.meet(saysOf(user)) | widen(holder, at(user))) == Changed::Yes)
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
