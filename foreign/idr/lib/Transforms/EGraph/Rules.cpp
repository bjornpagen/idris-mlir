// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The specification's rules, read where the compiler is built: the
// generated tables, the kinds they name and the runtime meanings of the
// ops, the rounds that saturate a function's classes under them, the
// matcher and the builder of a right side over them, the interval a built
// node's kind gives it, and the dispatch of the hand skeleton rules. A
// pattern is a constant of the specification, so a match's stack of
// choices is bounded by the specification, never by the input.
//
// The skeleton rules are each area's hand classes, declared where the
// specification names them; the generated tables include every header
// that declares one, and the classes of the upstream ops they admit are
// declared by those ops' dialects, included first.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <span>
#include <utility>

#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;

namespace idr::egraph::detail {

std::uint32_t nodesPerOp() { return generated::nodesPerOp; }

namespace {

consteval std::uint32_t widestOf() {
  std::uint32_t widest = 0;
  for (const table::Rule &rule : generated::rules)
    for (std::uint32_t at = rule.rhs; at < rule.rhs + rule.rhsSize; ++at)
      if (generated::patterns[at].kind == table::PatternKind::Node)
        widest = std::max<std::uint32_t>(widest, generated::patterns[at].arity);
  return widest;
}

} // namespace

std::uint32_t widestSide() {
  static constexpr std::uint32_t widest = widestOf();
  return widest;
}

namespace {

template <class... Rs>
constexpr bool everySkeletonRule(table::RuleList<Rs...>) {
  return (SkeletonRule<Rs> && ...);
}
static_assert(everySkeletonRule(generated::SkeletonRules{}),
              "every skeleton rule the specification names meets the engine's concept");

// The graph computes an op only through its meaning: its runtime function,
// which an op whose upstream fold calls the compiling machine's C library
// has none of, or, on the Doubles list, the APFloat operation its fold
// applies, which no such op is on: so the graph never folds one.
template <class Op, class... Ops>
constexpr bool among = (std::same_as<Op, Ops> || ...);

template <class... Never, class... Computed>
constexpr bool noneComputed(table::OpList<Never...>, table::OpList<Computed...>) {
  return ((!fold::Folds<Never> && !among<Never, Computed...>) && ...);
}
static_assert(noneComputed(generated::NeverFolded{}, generated::ComputedOnDoubles{}),
              "an op whose fold computes on the compiling machine has no meaning in the graph");

// Whether a rule's right side builds a node of the kind numbered `kind`.
consteval bool builtByARule(std::uint16_t kind) {
  for (const table::Rule &rule : generated::rules)
    for (std::uint32_t at = rule.rhs; at < rule.rhs + rule.rhsSize; ++at)
      if (generated::patterns[at].kind == table::PatternKind::Node &&
          generated::patterns[at].op == kind)
        return true;
  return false;
}

// An op on Doubles has a meaning as an op of the input alone, so a pattern
// may match one but no right side builds one: a node built of it would
// have nothing to compute it by.
template <class... Named, class... Computed>
consteval bool noneBuilt(table::OpList<Named...>, table::OpList<Computed...>) {
  std::uint16_t kind = 0;
  bool none = true;
  ((none = none && !(among<Named, Computed...> && builtByARule(kind)), ++kind), ...);
  return none;
}
static_assert(noneBuilt(generated::Kinds{}, generated::ComputedOnDoubles{}),
              "a rule builds an op on Doubles, which has a meaning only as an op of the input");

template <class... Ops>
void listKinds(table::OpList<Ops...>, MLIRContext *context,
               std::vector<std::pair<TypeID, Kinds::OfOp>> &byTypeId,
               std::vector<std::optional<RegisteredOperationName>> &names) {
  std::uint16_t kind = 0;
  (
      [&] {
        byTypeId.emplace_back(TypeID::get<Ops>(),
                              Kinds::OfOp{kind, std::nullopt, Borrowed(), std::nullopt});
        names.push_back(RegisteredOperationName::lookup(TypeID::get<Ops>(), context));
        ++kind;
      }(),
      ...);
}

template <class... Rs>
std::optional<Decided> decideAll(table::RuleList<Rs...>, Operation *op,
                                 const OperandFacts &facts) {
  std::optional<Decided> decided;
  std::uint32_t index = 0;
  auto ask = [&]<class R>() {
    if (!decided)
      if (auto root = dyn_cast<typename R::Root>(op))
        if (std::optional<Edit> edit = R::decide(root, facts))
          decided = Decided{std::move(*edit), index};
    ++index;
  };
  (ask.template operator()<Rs>(), ...);
  return decided;
}

template <class... Rs>
void rewriteOne(table::RuleList<Rs...>, std::uint32_t rule, Operation *op, const Rewrite &rewrite,
                RewriterBase &rewriter) {
  std::uint32_t index = 0;
  auto run = [&]<class R>() {
    if (index++ == rule)
      R::rewrite(cast<typename R::Root>(op), rewrite, rewriter);
  };
  (run.template operator()<Rs>(), ...);
}

} // namespace

// Each kind, each meaning, each op's borrowed operands and each guard's
// decision by its op's TypeID, one entry an op, sorted for the one lookup
// an op's class needs; and each kind's meaning of a built node by its
// number, which a node a rule built reads.
Kinds makeKinds(MLIRContext *context) {
  Kinds out;
  std::vector<std::pair<TypeID, Kinds::OfOp>> entries;
  listKinds(generated::Kinds{}, context, entries, out.names);
  for (auto [id, meaning] : meanings())
    entries.emplace_back(id, Kinds::OfOp{std::nullopt, meaning, Borrowed(), std::nullopt});
  for (auto [id, borrowed] : borrowings())
    entries.emplace_back(id, Kinds::OfOp{std::nullopt, std::nullopt, borrowed, std::nullopt});
  for (auto [id, decision] : decisions())
    entries.emplace_back(id, Kinds::OfOp{std::nullopt, std::nullopt, Borrowed(), decision});
  llvm::sort(entries, [](const auto &a, const auto &b) { return Kinds::before(a.first, b.first); });
  for (const auto &[id, of] : entries) {
    if (out.byTypeId.empty() || out.byTypeId.back().first != id) {
      out.byTypeId.emplace_back(id, of);
      continue;
    }
    Kinds::OfOp &into = out.byTypeId.back().second;
    if (of.kind)
      into.kind = of.kind;
    if (of.meaning)
      into.meaning = of.meaning;
    if (of.decision)
      into.decision = of.decision;
    into.borrowed = into.borrowed | of.borrowed;
  }
  out.built.assign(out.names.size(), std::nullopt);
  for (const auto &[id, of] : out.byTypeId)
    if (of.kind && of.meaning)
      out.built[*of.kind] = of.meaning->ofBuilt;
  return out;
}

std::optional<Decided> Function::decideSkeleton(Operation *op, const OperandFacts &facts) const {
  return decideAll(generated::SkeletonRules{}, op, facts);
}

void Function::rewriteSkeleton(const Pending &pending, RewriterBase &rewriter) {
  rewriteOne(generated::SkeletonRules{}, pending.rule, pending.root, pending.rewrite, rewriter);
}

//===----------------------------------------------------------------------===//
// The rounds
//===----------------------------------------------------------------------===//

namespace {

// The kind a node pattern names it by, if it has one: an op of the input
// where a rule names its op, or one a right side built. An atom has none.
std::optional<std::uint16_t> kindOf(const Node &node) {
  return match(node.what, [](const node::Input &op) { return op.kind; },
               [](const node::Built &op) { return std::optional(op.kind); },
               []<Atom N>(const N &) { return std::optional<std::uint16_t>(); });
}

} // namespace

// The build's own unions repaired, then round after round until one adds
// nothing or the budget is spent. A round that goes on made a node or a
// union; a node is made only below the budget, and a union leaves one
// class fewer, so the rounds end.
void Function::saturate() {
  rebuild();
  while (nodes.size() < budget && round() == Changed::Yes) {
  }
}

// Each node of the graph as it stood, in creation order, tried against the
// rules rooted at its kind, in the generated order: where one matches, its
// right side is built and its class united with the root's. A union is
// paid by the rebuild after the round, and a node a side builds is in a
// class of its own until then, so every match of the round reads the
// classes as they stood: their members, their facts and their operands.
Changed Function::round() {
  std::uint64_t made = nodes.size(), merged = unions;
  std::uint32_t stood = static_cast<std::uint32_t>(nodes.size());
  for (std::uint32_t n = 0; n < stood; ++n) {
    NodeId root(n);
    std::optional<std::uint16_t> kind = kindOf(at(root));
    // An op no pattern names roots no rule.
    if (!kind)
      continue;
    for (std::uint32_t r = generated::rulesOfKind[*kind]; r < generated::rulesOfKind[*kind + 1];
         ++r) {
      ++steps;
      const table::Rule &rule = generated::rules[r];
      std::optional<Bindings> bindings = matchAt(rule, root);
      if (!bindings)
        continue;
      // A right side built grows the node table, which moves the node, so
      // its type is read first.
      Type type = at(root).type;
      std::uint32_t side = rule.rhs;
      std::optional<ClassId> built = buildSide(rule, *bindings, side, type);
      // A specification sort is coarser than an MLIR type, which holds index
      // terms: a right side whose class is of another type here does not
      // apply here, since no rule changes a value's type.
      if (built && at(*built).type == type)
        (void)unite(classOfNode(root), *built);
    }
  }
  rebuild();
  return nodes.size() != made || unions != merged ? Changed::Yes : Changed::No;
}

//===----------------------------------------------------------------------===//
// Matching
//===----------------------------------------------------------------------===//

// The left side's patterns are matched in preorder, each operand pattern
// against the class its node's operand names: a variable binds the class,
// or meets the class it bound before (a repeated variable is an equality);
// a literal is the class's integer; a node pattern takes a member of the
// class of its kind and arity, whose operands are matched next. Taking a
// member is a choice: where what follows fails, or the rule's conditions
// do not hold of what was bound, the latest choice with a member left
// takes the next instead, so a match is found wherever one exists. The
// first found is the match: one per rule and root a round. Every class a
// match reads was a root when the round began, and a union of the round
// owes its meet to the rebuild, so its members and facts are its own as
// they stood.
std::optional<Bindings> Function::matchAt(const table::Rule &rule, NodeId root) const {
  const std::uint32_t end = rule.lhs + rule.lhsSize;
  std::uint32_t at = rule.lhs;
  // The classes the patterns ahead match, the next last.
  SmallVector<ClassId, 8> ahead;
  Bindings bindings;
  bindings.vars.resize(rule.vars);
  // A member taken for the node pattern at `at`, with what stood before it
  // was taken and the member to take instead.
  struct Choice {
    std::uint32_t at;
    std::optional<NodeId> next;
    SmallVector<ClassId, 8> ahead;
    Bindings bindings;
  };
  SmallVector<Choice, 4> choices;

  // `n` taken for the node pattern at `at`, where it is of the pattern's
  // kind and arity: its operands go ahead, the first next.
  auto enter = [&](NodeId n) {
    const Node &node = this->at(n);
    const table::PatternNode &pattern = generated::patterns[at];
    if (kindOf(node) != pattern.op || node.children.count != pattern.arity)
      return false;
    for (ClassId operand : llvm::reverse(childrenOf(node)))
      ahead.push_back(operand);
    ++at;
    return true;
  };
  // The first member from `from` on that the node pattern at `at` takes.
  auto take = [&](std::optional<NodeId> from) {
    for (std::optional<NodeId> member = from; member; member = nextMember[member->index()]) {
      Choice choice{at, nextMember[member->index()], ahead, bindings};
      if (enter(*member)) {
        choices.push_back(std::move(choice));
        return true;
      }
    }
    return false;
  };
  // Back to the latest choice that has a member left, taking it.
  auto retreat = [&] {
    while (!choices.empty()) {
      Choice choice = choices.pop_back_val();
      at = choice.at;
      ahead = std::move(choice.ahead);
      bindings = std::move(choice.bindings);
      if (take(choice.next))
        return true;
    }
    return false;
  };
  auto conditionsHold = [&] {
    std::span<const table::Condition> conditions =
        std::span<const table::Condition>(generated::conditions)
            .subspan(rule.conditions, rule.conditionCount);
    return llvm::all_of(conditions, [&](const table::Condition &c) { return holds(c, bindings); });
  };

  // The root is the node, not its class: each member of a class is a root
  // of its own.
  if (!enter(root))
    return std::nullopt;
  for (;;) {
    if (at == end) {
      if (conditionsHold())
        return bindings;
    } else {
      ClassId cls = ahead.pop_back_val();
      const table::PatternNode &pattern = generated::patterns[at];
      switch (pattern.kind) {
      case table::PatternKind::Var: {
        std::optional<ClassId> &bound = bindings.vars[pattern.var];
        if (!bound || *bound == cls) {
          bound = cls;
          ++at;
          continue;
        }
        break;
      }
      case table::PatternKind::Literal: {
        std::optional<APInt> value = this->at(cls).facts.integer();
        if (value && value->getSignificantBits() <= 64 &&
            value->getSExtValue() == pattern.literal) {
          ++at;
          continue;
        }
        break;
      }
      case table::PatternKind::Node:
        if (take(this->at(cls).first))
          continue;
        break;
      }
    }
    if (!retreat())
      return std::nullopt;
  }
}

// A side condition, read off the bound class's facts as the round found
// them. A constant is one of any kind: a rule that combines two constants
// leaves its new node to compute them, as a string's or a big's meaning
// does. Clean holds of every class the e-graph holds: a node floats only
// where nothing orders it, a call only where its row carries neither crash
// nor divergence, and a leaf's maker stays in the skeleton whatever a rule
// drops.
bool Function::holds(const table::Condition &condition, const Bindings &bindings) const {
  const Facts &known = at(*bindings.vars[condition.var]).facts;
  switch (condition.kind) {
  case table::ConditionKind::IsConstant:
    return known.isConstant();
  case table::ConditionKind::PowerOfTwo: {
    std::optional<APInt> value = known.integer();
    return value && value->isStrictlyPositive() && value->isPowerOf2();
  }
  case table::ConditionKind::InRange:
    return known.range && known.range->smin().getSignificantBits() <= 64 &&
           known.range->smax().getSignificantBits() <= 64 &&
           known.range->smin().getSExtValue() >= condition.lo &&
           known.range->smax().getSExtValue() <= condition.hi;
  case table::ConditionKind::Clean:
    return true;
  }
  return false;
}

// The interval a node a right side built has: the one its kind's range
// function gives its operands' intervals as their roots now hold them, an
// operand with none its type's whole width (a kind with a range function
// takes integers), where the kind has one. No op is made to fold it: over
// constants, the interval's one value is the integer it is.
std::optional<ConstantIntRanges> Function::intervalOf(const node::Built &op, Type type,
                                                      std::span<const ClassId> operands) const {
  const std::optional<table::IntRangeFn> &range = generated::intRanges[op.kind];
  if (!range)
    return std::nullopt;
  SmallVector<ConstantIntRanges, 4> inputs;
  for (ClassId operand : operands) {
    const Facts &known = factsOf(operand);
    inputs.push_back(known.range ? *known.range
                                 : ConstantIntRanges::maxRange(
                                       ConstantIntRanges::getStorageBitwidth(at(operand).type)));
  }
  return (*range)(inputs, type);
}

// The right side's subtree at `at`, built bottom-up: a variable is its
// class; a literal the integer the dialect reads it as at the type its
// place takes, a value the write-back makes an attribute, and none where it
// is no value of that type, the type has no integer form or the budget is
// spent, so the rule does not apply there; a node made over its operands'
// classes, of `type` at the top and of its first operand's type below (the
// arithmetic a rule builds keeps its operands' type).
std::optional<ClassId> Function::buildSide(const table::Rule &rule, const Bindings &bindings,
                                           std::uint32_t &at, Type type) {
  const table::PatternNode &pattern = generated::patterns[at++];
  switch (pattern.kind) {
  case table::PatternKind::Var:
    return bindings.vars[pattern.var];
  case table::PatternKind::Literal: {
    std::optional<APInt> value = integerAt(type, pattern.literal);
    if (!value)
      return std::nullopt;
    return integer(*value, type);
  }
  case table::PatternKind::Node: {
    SmallVector<ClassId, 4> operands;
    for (std::uint8_t i = 0; i < pattern.arity; ++i) {
      Type place = operands.empty() ? type : this->at(operands.front()).type;
      std::optional<ClassId> operand = buildSide(rule, bindings, at, place);
      if (!operand)
        return std::nullopt;
      operands.push_back(*operand);
    }
    // A kind whose dialect the context has not loaded is no op to build.
    const std::optional<RegisteredOperationName> &name = kinds.names[pattern.op];
    if (!name)
      return std::nullopt;
    return insert(node::Built{pattern.op, *name}, type, operands);
  }
  }
  return std::nullopt;
}

} // namespace idr::egraph::detail
