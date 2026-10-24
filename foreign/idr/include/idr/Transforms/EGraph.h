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
// against: the shape of the printed rule tables, the concept a hand
// skeleton rule meets, and the constants such a rule reads.
#ifndef IDR_TRANSFORMS_EGRAPH_H
#define IDR_TRANSFORMS_EGRAPH_H

#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Numeric/Intervals.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

// The runtime's C ABI: the strings and bigs the graph's constants hold.
#include "idris_rt.h"

#include <bit>
#include <concepts>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <utility>
#include <variant>

namespace idr {

#define GEN_PASS_DECL_IDRSIMPLIFY
#include "idr/Transforms/Passes.h.inc"

// A guard op, whose decision a skeleton rule reads (OperandFacts), complete
// where the engine's tables answer it.
class GuardOpInterface;

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
// would compute on the compiling machine), `ComputedOnDoubles` (an OpList
// of upstream's float ops whose result IEEE 754 fixes, which the graph
// computes on its Double values), `SkeletonRules` (a RuleList of
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

enum class ConditionKind : std::uint8_t { IsConstant, InRange, Clean };
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

//===----------------------------------------------------------------------===//
// The graph's constants
//===----------------------------------------------------------------------===//
// A constant the graph knows is a value of its own, never an attribute,
// until the write-back places it; a rule reads it as such.

// A string as the runtime holds it, one reference of the graph's own: two
// are one constant exactly when their bytes are. A rule reads one through
// a borrowed pointer, so what it reads needs no symbol of the engine's.
class Text {
public:
  // The reference the runtime gave, which the graph now holds.
  static Text adopt(const idris_rt_str *made) { return Text(made); }
  // Another reference to a string held elsewhere.
  static Text share(const idris_rt_str *s);
  Text(const Text &other) : Text(share(other.s)) {}
  Text(Text &&other) noexcept : s(std::exchange(other.s, nullptr)) {}
  Text &operator=(Text other) noexcept {
    std::swap(s, other.s);
    return *this;
  }
  ~Text();

  const idris_rt_str *get() const { return s; }
  llvm::StringRef bytes() const { return llvm::StringRef(idris_rt_str_bytes(s), s->bytes); }
  friend bool operator==(const Text &a, const Text &b) { return a.bytes() == b.bytes(); }

private:
  explicit Text(const idris_rt_str *s) : s(s) {}
  // Null only once moved from.
  const idris_rt_str *s;
};

// A Double by its IEEE bits, so two are one constant exactly when their
// bits are: 0.0 and -0.0 are two, as the program tells them apart.
struct Real {
  std::uint64_t bits;

  double value() const { return std::bit_cast<double>(bits); }
  friend bool operator==(Real, Real) = default;
};

// A big past the small range as the runtime holds it, a cell of limbs, one
// reference of the graph's own: two are one constant exactly when the
// runtime's comparison orders them equal. A big in the small range is an
// integer, the one value of its interval.
class Big {
public:
  static Big adopt(idris_rt_big made) { return Big(made); }
  static Big share(idris_rt_big b);
  Big(const Big &other) : Big(share(other.word)) {}
  Big(Big &&other) noexcept : word(std::exchange(other.word, smallZero)) {}
  Big &operator=(Big other) noexcept {
    std::swap(word, other.word);
    return *this;
  }
  ~Big();

  idris_rt_big get() const { return word; }
  friend bool operator==(const Big &a, const Big &b);

private:
  explicit Big(idris_rt_big word) : word(word) {}
  // A big moved from holds the small 0, the word 2 * 0 + 1, which has no
  // cell to release.
  static constexpr idris_rt_big smallZero = 1;
  idris_rt_big word;
};

struct Part;

// A constructor or closure constant: one an op of the input holds, read as
// the attribute it holds, or one the graph built of its parts, which the
// write-back makes an attribute of where it places it, and nothing before.
// Two are one constant where both are held as one attribute, or both built
// alike; a built one and a held one equal to it are two, which only shares
// less. A copy shares the parts.
class Data {
public:
  // A constructor or closure constant an op of the input holds.
  static Data held(mlir::Attribute value);
  // `data`'s one constructor, with `fields`.
  static Data constructor(DataType data, llvm::SmallVector<Part, 2> fields);
  // A closure of `callee` with `captures`.
  static Data closure(mlir::FlatSymbolRefAttr callee, llvm::SmallVector<Part, 2> captures);

  // The attribute an op of the input holds; null for one the graph built.
  mlir::Attribute heldValue() const;
  // A built constructor's data type, null for any other.
  DataType builtData() const;
  // A built closure's function, null for any other.
  mlir::FlatSymbolRefAttr builtCallee() const;
  // A built constant's fields or captures, none for a held one.
  llvm::ArrayRef<Part> parts() const;
  // A constructor's tag, held or built; none for a closure.
  std::optional<Tag> tag() const;
  std::size_t hash() const;

  friend bool operator==(const Data &a, const Data &b);

private:
  struct Node;
  explicit Data(std::shared_ptr<const Node> node) : node(std::move(node)) {}
  std::shared_ptr<const Node> node;
};

// What the graph knows a value to be where no interval says it: a string,
// a Double, a big past the small range, or a constructor or closure
// constant.
using Constant = std::variant<Text, Real, Big, Data>;

// A field of a constructor constant or a capture of a closure constant the
// graph built: the integer or the constant the operand it was built of is,
// with that operand's type, at which the write-back makes its attribute.
struct Part {
  std::variant<llvm::APInt, Constant> value;
  mlir::Type type;
};

// A constant a rule reads of a value, borrowed from its class while the
// rule decides: an integer, the one value of its interval (a big in the
// small range among them, as the runtime holds it in its word); or the
// string, the Double or the big past the small range its class holds.
using KnownConstant = std::variant<llvm::APInt, const Text *, Real, const Big *>;

// What the e-graph knows of any value of the function a rule is deciding
// in: an operand of its root, or a value a region of a producer yields
// (the choice per arm reads each arm's). Each answer is the value's
// class's, whatever member extraction chose: a fact any member gives holds
// of the one value. A value cast into or out of a linear position is its
// operand's at another grade, and each answer of it is its operand's: the
// constant it is, and the op that built it.
class OperandFacts {
public:
  explicit OperandFacts(const detail::Function &function) : function(function) {}
  // The constant the value is, where the graph knows it, whether an op of
  // the input held it or the graph computed it; none where it is no one
  // such constant (a data constant, a closure: see `held` and
  // `constructorTag`).
  std::optional<KnownConstant> constant(mlir::Value value) const;
  // The constructor of the constructor constant the value is, whether an op
  // of the input held it or the graph built it; none where it is none.
  std::optional<Tag> constructorTag(mlir::Value value) const;
  // The constant an op of a member holds, as it holds it; null where none
  // does. It is the one form of a constant the graph reads no value of (a
  // data constant, a closure), and what a hook that takes attributes is
  // given; a constant the graph computed holds no attribute, and `constant`
  // reads it.
  mlir::Attribute held(mlir::Value value) const;
  // The interval of an integer value, where the interval analysis knows
  // one; an interval of one value is the integer the value is.
  std::optional<mlir::ConstantIntRanges> range(mlir::Value value) const;
  // Whether a guard's condition holds, fails, or is unknown of what the
  // graph knows of its operands: its op's own decision, over each operand's
  // interval and the constant its class holds, whether an op held it or the
  // graph computed it.
  numeric::Known decision(GuardOpInterface guard) const;
  // How the value is built, where a member of its class says so: the op of
  // the input of class `OpT` a member is (a constructor a known-case rule
  // reads), one computable wherever the class is used, or else the one
  // that built the value a member casts; null where none is. A rule asks
  // for the op it reads by its class, so the answer is typed.
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
// What each function gives back and returns, as the optimizer decided it:
// inside idr-optimize the optimizer is idr-simplify's decide step, holding
// its final nodes' facts, and a parallel function pass may not read its
// siblings, so the optimizer hands the pass this table. A call is replaced
// by the argument its callee gives back whole where the call floats (its
// row carries neither crash nor divergence), and each result of a call is
// the constant its callee returns there, whatever the call does besides,
// since the callee computes the same value at every call: the graph reads
// both as facts of the call's results. The specializer reads the same
// table: a copy keyed to a weaker hold for a parameter keys each result
// that parameter may reach to that hold. A run that holds the table is a
// step of a round of idr-optimize, whose redirect keys each call after it,
// so there a string or a big the graph computes stands at a call's argument
// as static data, for that redirect to key the call by (Elaborate.cpp). The
// pipeline's own points run after the optimizer has rewritten every such
// call, read none, and have no specializer after them.

// A constant a function's final body returns as one of its results: the
// attribute the constant op its return reads holds, the dialect that
// materializes it, and the type it stands at, its op's: the function's own
// result type, or that type at the grade the value had before the return
// cast it into its one use. A call's result is that constant, or holds it
// at another grade, only where the call's index arguments leave the
// carrier as it is.
struct ReturnedConstant {
  mlir::Attribute value;
  mlir::Dialect *dialect;
  mlir::Type type;
};

class CalleeFacts {
public:
  explicit CalleeFacts(const solver::Editor &names)
      : names(&names), facts(names.size(), Published()) {}

  // `f`'s facts, once its component is final: what the identities solve
  // found it gives back, and the constant each of its results is, read off
  // `final`, its final body, where its return reads a constant op. The
  // optimizer's write, between its waves; the table grows with the
  // functions it made.
  void publish(solver::FunctionId f, identities::Facts given, FuncOp final);

  // The function `call` calls, as the program graph's editor resolves the
  // symbol it names: read once where a call enters a reader, which then
  // reads its callee's facts by id; none for a copy its wave made, which
  // the editor does not hold yet.
  std::optional<solver::FunctionId> calleeOf(CallOp call) const;

  // What `callee` gives back on every path and what may reach its results,
  // both empty for a callee not final.
  identities::FactsView of(solver::FunctionId callee) const;

  // What each result of `callee` is where its final body returns a
  // constant there, one entry per result; empty for a callee not final.
  llvm::ArrayRef<std::optional<ReturnedConstant>> returns(solver::FunctionId callee) const;

private:
  struct Published {
    identities::Facts given;
    llvm::SmallVector<std::optional<ReturnedConstant>, 1> returned;
  };
  // `callee`'s record, none for one inserted since the table last grew,
  // which no component has published yet.
  const Published *find(solver::FunctionId callee) const;

  const solver::Editor *names;
  IndexVector<solver::FunctionId, Published> facts;
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
