// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-simplify: the e-graph pass that takes the place of greedy rewriting
// and common subexpressions at every point of the pipeline that holds our
// ops, and as upstream's inliner's simplification. One function at a time,
// in parallel under the pass manager, it holds the function's floating
// values in its own typed tables over MLIR's ops, an e-graph: classes of
// equal values under a union-find, hash-consed and kept congruent,
// saturated by the specification's rules in rounds, each rule adding its
// right side to its left side's class. It keeps every op whose effects
// order it in a skeleton per region, extracts the cheapest form of each
// value and writes it back through MLIR's rewriter. Its output is the same
// bytes at any thread count.
//
// This header is what the specification's generator and the op lanes write
// against: the shape of the printed rule tables, and the concept a hand
// skeleton rule meets.
#ifndef IDR_TRANSFORMS_EGRAPH_H
#define IDR_TRANSFORMS_EGRAPH_H

#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Solver/ProgramGraph.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <concepts>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <variant>

namespace idr {

#define GEN_PASS_DECL_IDRSIMPLIFY
#include "idr/Transforms/Passes.h.inc"

namespace egraph {

//===----------------------------------------------------------------------===//
// The printed rule tables
//===----------------------------------------------------------------------===//
// specgen prints IdrisMLIR.Spec.Core.Rewrite's records as these constexpr
// tables into idr/IR/Generated/Rewrites.h.inc, inside namespace
// idr::egraph::generated: `patterns`, `conditions`, `rules` (sorted by root
// kind), `rulesOfKind` (kind k's rules are rules[rulesOfKind[k],
// rulesOfKind[k + 1])), `Kinds` (an OpList of every op kind a pattern
// names, a kind's number its position), `intRanges` (each kind's range
// function, by its number), `NeverFolded` (an OpList of the ops whose fold
// would compute on the compiling machine), `SkeletonRules` (a RuleList of
// the hand skeleton rule classes) and `nodesPerOp`. Nothing is built per
// function from them: the engine reads them where the compiler is built.
namespace table {

template <class... Ops>
struct OpList {
  static constexpr std::size_t size = sizeof...(Ops);
};
template <class... Rules>
struct RuleList {};

// A pattern, flattened in preorder: a node's operand patterns follow it.
enum class PatternKind : std::uint8_t { Var, Node, Literal };
struct PatternNode {
  PatternKind kind;
  // Node: the op kind, its position in Kinds; and which of its results.
  std::uint16_t op;
  std::uint8_t result;
  // Node: how many operand patterns follow.
  std::uint8_t arity;
  // Var: the variable.
  std::uint16_t var;
  // Literal: its value, at the type of the position it fills.
  std::int64_t literal;
};

enum class ConditionKind : std::uint8_t { IsConstant, PowerOfTwo, InRange, Clean };
struct Condition {
  ConditionKind kind;
  std::uint16_t var;
  // InRange: the closed interval.
  std::int64_t lo, hi;
};

// One rule, one way: its variables, its left side rooted at an op (a run of
// patterns whose first node is the root), its right side (a run of
// patterns), which joins the left side's class where it matches, both forms
// kept, and its conditions (a run of conditions).
struct Rule {
  std::uint16_t vars;
  std::uint32_t lhs, lhsSize;
  std::uint32_t rhs, rhsSize;
  std::uint32_t conditions, conditionCount;
};

// A kind's interval from its operands' intervals, for a node a rule built,
// where no op stands to be asked; `result` is the node's type.
using IntRangeFn = mlir::ConstantIntRanges (*)(llvm::ArrayRef<mlir::ConstantIntRanges>,
                                               mlir::Type result);

// A range function of one of the shapes upstream writes them in, by the
// arguments it takes after its operands' intervals.
template <auto F, class... Args>
concept RangeOver = requires(Args... args) {
  { F(args...) } -> std::same_as<mlir::ConstantIntRanges>;
};

// Each shape as an IntRangeFn, chosen by F's signature, so the generated
// table names upstream's function and the shape is never restated.
namespace range {
// One that reads overflow flags: a node a rule built has the op's default
// properties, which promise none.
template <auto F>
  requires RangeOver<F, llvm::ArrayRef<mlir::ConstantIntRanges>, mlir::intrange::OverflowFlags>
mlir::ConstantIntRanges by(llvm::ArrayRef<mlir::ConstantIntRanges> operands, mlir::Type) {
  return F(operands, mlir::intrange::OverflowFlags::None);
}
// An extension or a truncation: its one operand, to the result's width.
template <auto F>
  requires RangeOver<F, const mlir::ConstantIntRanges &, unsigned>
mlir::ConstantIntRanges by(llvm::ArrayRef<mlir::ConstantIntRanges> operands, mlir::Type result) {
  return F(operands[0], mlir::ConstantIntRanges::getStorageBitwidth(result));
}
// One that reads the operands alone, as an inline meaning over intervals
// does too.
template <auto F>
  requires RangeOver<F, llvm::ArrayRef<mlir::ConstantIntRanges>>
mlir::ConstantIntRanges by(llvm::ArrayRef<mlir::ConstantIntRanges> operands, mlir::Type) {
  return F(operands);
}
} // namespace range

template <auto F>
inline constexpr IntRangeFn rangeBy = &range::by<F>;

} // namespace table

//===----------------------------------------------------------------------===//
// Skeleton rules
//===----------------------------------------------------------------------===//
// A one-way rule over an op the skeleton orders, or over a region: hand
// C++ the specification names with the op it is rooted at. Once the
// function's e-graph is saturated and extracted, `decide` reads what it
// knows of the function's values and returns an edit or nothing. No skeleton
// rule makes an op with an identity, and none reorders two ops one
// resource orders.
//
// A function takes two turns at most, each an e-graph of its own, saturated
// in its rounds of the rules. In the first turn every skeleton rule
// decides; if any decided a Rewrite, the engine runs those rewrites on the
// function, region by region in the order the walk met them (each
// `R::rewrite` with the insertion point at its root, a root an earlier
// rewrite erased skipped, so a rewrite checks that its condition still
// holds of the root as it then is), builds the e-graph again over what
// they made, and decides again, a Rewrite now kept as it is. Then the
// Forward and Take edits of the last turn are carried out as the function
// is written back. So a rule may restructure its root's regions, and the
// e-graph simplifies what it made, with no turn beyond the second.

namespace detail {
// One function's e-graph, the engine's own (idr/Transforms/EGraph/Engine.h).
class Function;
} // namespace detail

// A cost in the program's units. It saturates at `most`, so no sum of
// costs wraps, and below it every op costs more than its operands, so
// extraction, which moves a class to an equal price only below `most`,
// closes no cycle.
class Cost {
public:
  static constexpr Cost of(std::uint32_t units) { return Cost(units); }
  static constexpr Cost most() { return Cost(0xffffffffu); }
  constexpr Cost plus(Cost other) const {
    std::uint64_t sum = std::uint64_t(units) + other.units;
    return sum > most().units ? most() : Cost(static_cast<std::uint32_t>(sum));
  }
  friend constexpr auto operator<=>(Cost, Cost) = default;

private:
  constexpr explicit Cost(std::uint32_t units) : units(units) {}
  std::uint32_t units;
};

// What the e-graph knows of any value of the function a rule is deciding
// in: an operand of its root, or a value a region of a producer yields
// (the choice per arm reads each arm's). Each answer is the value's
// class's, whatever member extraction chose: a fact any member gives holds
// of the one value.
class OperandFacts {
public:
  explicit OperandFacts(const detail::Function &function) : function(function) {}
  // The constant the value's class holds as an attribute, one an op of a
  // member holds; null where it holds none. An integer the graph computed
  // is a value and no attribute: it is the one value of the value's range.
  mlir::Attribute constant(mlir::Value value) const;
  // The interval of an integer value, where the interval analysis knows
  // one; an interval of one value is the integer the value is.
  std::optional<mlir::ConstantIntRanges> range(mlir::Value value) const;
  // How the value is built, where a member of its class says so: the op of
  // the input of class `OpT` a member is (a constructor a known-case rule
  // reads), one computable wherever the class is used; null where none is.
  // A rule asks for the op it reads by its class, so the answer is typed.
  template <class OpT>
  OpT builtBy(mlir::Value value) const;
  // What computing the value's chosen form costs, its operands included:
  // what a copy of a consumer into an arm weighs against a shared join.
  Cost cost(mlir::Value value) const;

private:
  const detail::Function &function;
};

// The edits a skeleton rule may ask for.
// Each result of the root becomes the operand at the position given.
struct Forward {
  llvm::SmallVector<unsigned, 2> operandOfResult;
};
// The root, a region op, becomes one of its regions, one that yields to
// the root: its block arguments bound to the root's operands at the
// positions given, its yielded values the root's results. The region's ops
// are written back in the root's place, in order. A region that ends
// otherwise (a crash, a jump out) is no region to take: its end would sit
// inside the root's block.
struct Take {
  unsigned region;
  llvm::SmallVector<unsigned, 2> operandOfArgument;
};
// The rule's own rewrite of the root and its regions, run between the two
// turns, handed what the rule chose while it could read the e-graph (the
// arms a dispatch is copied into, by index).
struct Rewrite {
  llvm::SmallVector<unsigned, 4> chosen;
};
using Edit = std::variant<Forward, Take, Rewrite>;

template <class R>
concept SkeletonRule =
    requires { typename R::Root; } &&
    requires(typename R::Root root, const OperandFacts &facts, mlir::RewriterBase &rewriter) {
      { R::decide(root, facts) } -> std::same_as<std::optional<Edit>>;
      { R::rewrite(root, Rewrite{}, rewriter) } -> std::same_as<void>;
    };

//===----------------------------------------------------------------------===//
// What the pass reads of callees
//===----------------------------------------------------------------------===//
// What each function gives back, as the optimizer decided it: inside
// idr-optimize the optimizer is idr-simplify's decide step, holding its
// final nodes' facts, and a parallel function pass may not read its
// siblings, so the optimizer hands the pass this table. A call is replaced
// by the argument its callee gives back whole where the call floats (its
// row carries neither crash nor divergence). The pipeline's own points run
// after the optimizer has rewritten every such call, and read none.
class CalleeFacts {
public:
  explicit CalleeFacts(const solver::Editor &names)
      : names(&names), facts(names.size(), identities::Facts()) {}

  // `f`'s facts, once its component is final: the optimizer's write,
  // between its waves; the table grows with the functions it made.
  void publish(solver::FunctionId f, identities::Facts given);

  std::span<const identities::GivesBack> of(mlir::FlatSymbolRefAttr callee) const;

private:
  const solver::Editor *names;
  IndexVector<solver::FunctionId, identities::Facts> facts;
};

} // namespace egraph

// The pass the optimizer runs in its inner pipeline, reading the table it
// decided; the pipeline's points take the generated createIdrSimplify().
std::unique_ptr<mlir::Pass> createIdrSimplify(const egraph::CalleeFacts &callees);

} // namespace idr

// What OperandFacts answers, inline over the engine's tables: a skeleton
// rule, wherever its library sits, reads it with no symbol of the engine's.
#include "idr/Transforms/EGraph/Engine.h"

#endif // IDR_TRANSFORMS_EGRAPH_H
