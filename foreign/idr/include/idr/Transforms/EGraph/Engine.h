// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One function's e-graph: its tables and its phases.
//
// Build: one walk in walk order. Each op is classified by its declared
// effects: an op with none (an op-level acquisition only reports) floats,
// and is a node hash-consed into a class; an op whose only effect is the
// identity of its result is a node of its own, never hash-consed, so no
// two such are ever one class, placed at most once per path; every other
// op, a region op, a call in tail position and a terminator stays in the
// skeleton of its region, in order, and so does an op whose value depends
// on its parent (DependsOnParent), which two parents would make two
// values. A node of the input is made with what it says of its value: an
// interval, by upstream's transfer function, whose one value, where it has
// one, is the integer it is; the constant it holds, read once from its
// attribute into a value of the graph's own; and, where its meaning is a
// runtime function, the constant that function computes from its
// operands' constants, the one fold's value instance (IR/Fold.h), or, for
// an op of upstream's on Doubles whose result IEEE 754 fixes, the
// operation its own fold applies, so no attribute is made. An op whose
// fold gives the value of an operand, of its own or of the op that built
// one (a field a constructor was given, a cast of a cast), is that value's
// class, with no node of its own. An op that keeps its operand's value at
// another grade (a cast into or out of a linear position) is a node of its
// own, its grade the verifier's, whose value is its operand's: what it
// says is the constant its operand is, and how it is built is how its
// operand is (keptBy), so a fold or a skeleton rule reads a value cast into
// a linear position as the value it is. A node a right
// side builds has no op to ask and none is made for it: its interval is
// its kind's range function over its operands' intervals, from the
// generated table, and its constant its kind's runtime meaning over
// theirs. A constant is a value until the write-back makes its attribute,
// of five kinds: an integer, the one value of an interval (a big in the
// small range among them, as the runtime holds it in its word); a string's
// bytes; a Double's bits; a big past the small range, as the runtime holds
// it, in a cell, with the interval its sign gives; and a constructor or a
// closure, held as the attribute an op of the input holds, or built of its
// parts by the composite folds (IR/FoldParts.h), made an attribute only
// where the write-back places it. One is hash-consed
// by its value, and has a node only at a type its constant op stands at;
// an op of the input whose meaning computes such a constant is it, with no
// node of its own. A call's result is the constant its callee returns
// there, as the callees' table says, the attribute its final body's
// constant op holds, read once into the graph's own. A repeated read in a
// region with no write of what it reads between merges into the first, and
// a repeated op of the region's parent into the first; the skeleton rules
// decide their edits. An op's regions are numbered one after another as
// the walk first enters the op, and the region graph of the region-branch
// ops is read off them once: each branch point (an op entering its regions,
// a terminator leaving its region), the edges it may take, and what each
// edge passes the arguments of the region it enters or the results of the
// op it leaves (Regions.cpp).
//
// Saturate: the specification's rules, in rounds. A round first gives the
// leaves what the skeleton says of them: each input of a region-branch
// op's successor the join of what the edges that may run pass it, the
// edges that run read from the body down over the constants their points'
// operands hold; each skeleton op's results its intervals; and a guard's
// result, where its condition holds, its checked operand's facts. Then it
// tries each rule, in the generated order, at each node of the kind it is
// rooted at, over the graph as it stood when the round began: a rule that
// matches builds its right side and unites that class with the root's, so
// both forms stay. A union links one root of the union-find under the
// other at once and owes the merge of the two classes' contents (members,
// users, facts) to the rebuild, so nothing a round's matches read changes
// while they read. The rebuild pays what is owed, then repairs each class whose
// members grew: each node that reads it is keyed again by its operands'
// roots, and one that has become equal to another keyed node unites their
// classes, until no union is owed; so congruence holds again after every
// round, and the cost of keeping it is paid once a round rather than once
// a union. A class's facts are what each member says of its one value,
// met: each holds of the value, so their meet does, and a meet that comes
// out empty means a fact was wrong. A node reads its operands' facts
// through their roots when it reads them: when it is made, and when a
// rebuild repairs it, where what it now says narrows its class; a class so
// narrowed has its users read again at the next round's rebuild, and a
// class whose facts are one constant, and that holds no fresh identity,
// holds that constant.
//
// The rounds end by construction: a round that makes no node and unites no
// two classes is the last; a node is made only while the function's budget
// of nodes is not spent, and each union leaves one class fewer, so no more
// rounds run than the budget's nodes and the classes together. A spent
// budget stops them and leaves the function less optimized, never refused.
// The strings and bigs the graph computes take the runtime's memory, as
// many bytes at most as its nodes may: a constant past that is not kept,
// and the op that computes it stays, so a chain that doubles a string
// stops where the function's own size does.
//
// A class can be computed only where its members can: a leaf only in its
// region, which a union may put in a class also used outside it. So each
// class keeps its reach, the outermost region where one of its members can
// be computed; a node whose operands share no region where each can be
// computed is not built, and two classes whose reaches do not nest do not
// unite, since nothing would compute the one value at both their uses.
// The reaches are spread to their fixpoint once the rounds are done: each
// moves only outward, so this ends.
//
// Extract: each class's cheapest member by the engine's own cost (an op
// one, a value a skeleton op or a region gives one, a constant none), among
// the members computable in its reach, which
// are computable at every use of the class. A member may read its own
// class, so prices are relaxed over every node in creation order, at most
// one pass per class, until a pass changes none. A class moves to another
// member only for a lower price, or an equal one and a larger id (the
// newer form) below the cost's saturation, so the chosen members close no
// cycle.
//
// Elaborate: the regions in program order, each skeleton op's operands
// written back where they are demanded, a value placed in the scope that
// demands it unless an enclosing scope already holds it, a constant made
// its attribute there, the one place the graph makes one, the skeleton's
// edits carried out; then the input's floating ops, unused, are erased. A
// string or a big the graph computed whose constant op does not stand at
// its class's type, a hold that counts, is static data at each use that
// takes it so, an operand the op's runtime function borrows or a field of
// a constructor, made there at its class's type with its hold made static;
// every other use (a call, a return, a yield, an op whose result carries
// it on) takes the op that computes it, applied. The class each skeleton
// op's operand names is read off the input before any edit replaces a
// value, and a value an edit replaces (a forwarded result, a taken region's
// argument or result) becomes the class of the value it is given, which
// later uses demand as they take it.
//
// Every id is minted by the table that holds it and never leaves the
// function; no map holds per-node state by an IR handle but the value
// numbering, which lives while the function is read; nothing recurses on
// the input: the walks are MLIR's, the regions' stack and a match's
// choices are explicit, and a demand's postorder is the shared depth-first
// walk. Every table sized by the function, and the regions' stack, is the
// footprint's.
#ifndef IDR_TRANSFORMS_EGRAPH_ENGINE_H
#define IDR_TRANSFORMS_EGRAPH_ENGINE_H

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/UnionFind.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Changed.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/EGraph.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <concepts>
#include <cstdint>
#include <limits>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace idr::egraph::detail {

struct ValueTag {
  using Minter = solver::Numbering<ValueTag>;
};
// A value of the input function, by its place in the walk.
using ValueId = Id<ValueTag>;

class Function;
struct NodeTag {
  using Minter = Function;
};
struct ClassTag {
  using Minter = Function;
};
struct RegionTag {
  using Minter = Function;
};
struct UseTag {
  using Minter = Function;
};
struct PointTag {
  using Minter = Function;
};
struct EdgeTag {
  using Minter = Function;
};
struct TargetTag {
  using Minter = Function;
};
using NodeId = Id<NodeTag>;
using ClassId = Id<ClassTag>;
using RegionId = Id<RegionTag>;
// An operand of a node, by its place among every node's operands.
using UseId = Id<UseTag>;
// The region graph's: a branch point, an edge of one, and a successor an
// edge enters.
using PointId = Id<PointTag>;
using EdgeId = Id<EdgeTag>;
using TargetId = Id<TargetTag>;

// A run of one of the function's flat arrays.
struct Run {
  std::uint32_t first = 0, count = 0;
};

// Whether a node may stand for an equal one: a value with no identity is
// shared; one whose result takes a fresh identity is its own.
enum class Identity : std::uint8_t { Shared, Own };

// Whether an op's result is a value it makes, or its first operand's value
// at another grade, as an op that keeps its operand's value (SameValue)
// says: read off the op once, where the walk makes its node.
enum class Keeps : std::uint8_t { Nothing, Operand };

// How the write-back writes an integer of a type: a word of the type, or
// every element of a shaped value of a static shape the same word, each
// arith's constant; or a big or a natural used any number of times, whose
// integer in the small range the runtime holds in its word, idr.constant's,
// which stands at any hold. A type whose integers have no constant op of
// their own at it has none, and an integer of it stays the op that
// computes it: a word or a big used once, and a numeral.
enum class IntegerForm : std::uint8_t { Word, Splat, Small };
std::optional<IntegerForm> integerFormOf(mlir::Type type);

// The graph's constants (Text, Real, Big, the closed sum Constant of them)
// are the interface's, since a skeleton rule reads them (EGraph.h).

llvm::hash_code hash_value(const Constant &constant);
// The bytes of the runtime's memory it takes: a string's or a big's cell; a
// Double takes none.
std::uint64_t bytesOf(const Constant &constant);
// Whether its constant op stands at `type`: a Double's, arith.constant, at
// f64; a string's or a big's, idr.constant, where static data does.
bool placedAt(const Constant &constant, mlir::Type type);
// The type at which static data stands for a value of `type` that the graph
// knows to be `constant`, a string or a big: `type` with its hold made
// static, where the grade order lets static data stand where `type` is
// asked (a hold that claims nothing) and idr.constant stands there; none
// for a Double, which holds no reference, and for any other type.
std::optional<mlir::Type> staticFormOf(const Constant &constant, mlir::Type type);

struct Class;
struct Facts;

// An op's meaning over its operands' classes, each a constant, as the
// graph's own values (Values.cpp): of an op of the input, read with its
// properties; and, for an op a rule may build, of a node a rule built, with
// its kind's default properties. Upstream's ops on Doubles have the first
// alone: no rule builds one, and a pattern carries no predicate or
// rounding for one to be built with.
// A meaning of an input op reads the function's graph where it asks how an
// operand was built (the composite folds' `builtBy`).
using MeaningOfInput = std::optional<Facts> (*)(const Function &function, mlir::Operation *op,
                                                mlir::Type type,
                                                llvm::ArrayRef<const Class *> operands);
using MeaningOfBuilt = std::optional<Facts> (*)(mlir::Type type,
                                                llvm::ArrayRef<const Class *> operands);
// The value an op of the input gives in place of a constant, where its fold
// gives an operand's value (fold::Folded): the class of that value.
using GivenOfInput = std::optional<ClassId> (*)(const Function &function, mlir::Operation *op,
                                                llvm::ArrayRef<const Class *> operands);
struct Meaning {
  MeaningOfInput ofInput;
  std::optional<MeaningOfBuilt> ofBuilt;
  std::optional<GivenOfInput> given;
};

// A guard op's decision of its condition over its operands' classes, each
// read as the graph's own values (Values.cpp): its op's own `decide`.
using Decision = numeric::Known (*)(llvm::ArrayRef<const Class *> operands);

// The operands an op's runtime function takes as a string or a big, by
// position: references the function borrows, neither keeping nor releasing
// them, so what holds them is the caller's affair, as the op's constraint
// on each says (read in place, at any hold). Read off the op's generated
// ABI row, which has one kind per operand.
class Borrowed {
public:
  // The most operands a row's positions are kept for.
  static constexpr unsigned most = 32;

  constexpr Borrowed() = default;
  constexpr Borrowed with(unsigned position) const {
    assert(position < most && "a row's operands fit its positions");
    Borrowed out = *this;
    out.bits |= std::uint32_t{1} << position;
    return out;
  }
  constexpr Borrowed operator|(Borrowed other) const {
    Borrowed out = *this;
    out.bits |= other.bits;
    return out;
  }
  constexpr bool has(unsigned position) const {
    return position < most && ((bits >> position) & 1u) != 0;
  }
  constexpr bool empty() const { return bits == 0; }

private:
  std::uint32_t bits = 0;
};

// What a node is.
namespace node {
// A value the e-graph does not see through: an argument of the function or
// of a region, or a result of a skeleton op; it exists only in the region
// it is of, its home.
struct Leaf {
  mlir::Value value;
  RegionId home;
};
// An op of the input, which stands for itself: its kind where a rule names
// it, whether its result takes a fresh identity, whether that result is
// its first operand's value, and its runtime meaning where it has one.
struct Input {
  mlir::Operation *origin;
  std::optional<std::uint16_t> kind;
  Identity identity;
  Keeps keeps;
  std::optional<MeaningOfInput> meaning;
  std::optional<GivenOfInput> given;
};
// An op a rule's right side built: the op of its kind the write-back would
// make, of its type and the op's default properties. A rule makes nothing
// with an identity, so it is shared.
struct Built {
  std::uint16_t kind;
  mlir::RegisteredOperationName name;
};
// A constant an op of the input holds as an attribute, which the graph
// reads once into its own values and never makes; materialized by
// `dialect`'s hook, the same attribute, where it is placed.
struct Held {
  mlir::Attribute value;
  mlir::Dialect *dialect;
};
// An integer the graph knows, by an interval of one value or a rule's
// literal: a value, made an attribute of `form` only where the write-back
// places it.
struct Integer {
  llvm::APInt value;
  IntegerForm form;
};
// A string, a Double or a big past the small range the graph knows: a
// value, made an attribute only where the write-back places it, and made a
// node only at a type its constant op stands at.
struct Known {
  Constant value;
};
} // namespace node
using What = std::variant<node::Leaf, node::Input, node::Built, node::Held, node::Integer,
                          node::Known>;

// A node that is no op: a leaf or a constant, of no operands. No node
// pattern matches it, it reads no class, and it costs nothing to place.
template <class N>
concept Atom = std::same_as<N, node::Leaf> || std::same_as<N, node::Held> ||
               std::same_as<N, node::Integer> || std::same_as<N, node::Known>;

struct Node {
  What what;
  mlir::Type type;
  Run children;
};

// What the graph knows of a value, each where known: the interval an
// integer lies in, whose one value, where it has one, is the integer it is
// (the rule upstream's range optimizations use); and the constant it is,
// of a kind no interval states. Both are values: the graph makes no
// attribute.
struct Facts {
  std::optional<mlir::ConstantIntRanges> range;
  std::optional<Constant> constant;

  // An interval of no width is upstream's mark for a value it does not see
  // as an integer (a string, a box), whose one "value" is no integer.
  std::optional<llvm::APInt> integer() const {
    if (!range || range->umin().getBitWidth() == 0)
      return std::nullopt;
    return range->getConstantValue();
  }
  // Whether it says the value is one constant, of any kind.
  bool isConstant() const { return constant || integer(); }
  // What is known of one value known two ways, both of which hold: it lies
  // in both intervals, and is either's constant (two constants of one value
  // are one). Whether this narrowed.
  Changed meet(const Facts &other);
  // What is known of a value that is one of two, each known its own way: it
  // lies in the union of their intervals, where both are intervals of one
  // width, and is their constant where both are that one constant.
  Facts joined(const Facts &other) const;
  // Whether it says nothing.
  bool empty() const { return !constant && (!range || range->umin().getBitWidth() == 0); }
};

// An operand of a node read as a use of the class it names: the node it is
// of, and the next use of the same class, so a class's users are a list
// that a union joins to another's in one step.
struct Use {
  NodeId user;
  std::optional<UseId> next;
};

struct Class {
  mlir::Type type;
  // What every member says of the class's one value, met. A root's is
  // current; a class linked under another gave its facts to its root when
  // the rebuild paid the union.
  Facts facts;
  // Its members, first to last through the nodes' next members, and how
  // many: the size the union-find links by.
  NodeId first, last;
  std::uint32_t size;
  // The uses of it, first to last, none before any node reads it.
  std::optional<UseId> firstUse, lastUse;
  // Own where a member takes a fresh identity: two such classes are two
  // values whatever a rule says of their contents, so they never unite.
  Identity identity;
  // The outermost region where a member can be computed, as the graph
  // last read its members: a leaf only in its home, any other node where
  // each operand can be. A member's region is this or inside it, and so is
  // every use of the class, since two classes unite only where one's reach
  // holds the other's; a reach only moves outward.
  RegionId reach;
};

// A union whose contents the rebuild still owes: `from`'s members, uses
// and facts go to `into`, which was its root when the union was made.
struct Owed {
  ClassId into, from;
};

// What becomes of a skeleton op when the function is written back.
struct Kept {};
// A rule's edit, by the rule's place in the generated list.
struct Decided {
  Edit edit;
  std::uint32_t rule;
};
// A repeated read: its results are an earlier op's.
struct Merged {
  mlir::Operation *into;
};
using Fate = std::variant<Kept, Decided, Merged>;

struct Skeletal {
  mlir::Operation *op;
  Fate fate;
  // A region op's first region: its regions were numbered one after
  // another as the walk entered them.
  std::optional<RegionId> regions;
};

struct Region {
  std::optional<RegionId> parent;
  std::uint32_t depth;
  mlir::Region *ir;
  Run skeleton;
  // The branch points whose choice is made in it, a run of `points`: each
  // region-branch op of its skeleton entering its regions, and its
  // terminator leaving it.
  Run points;
};

// How a branch point of the region graph chooses where control goes:
// a region-branch op entering its regions, or a terminator leaving its
// region, each the interface's own choice over its operands' constants.
enum class Branching : std::uint8_t { Enters, Leaves };

// A branch point: the op that chooses, how, and its edges, a run of
// `edges`, one per successor it may take whatever its operands are.
struct Point {
  mlir::Operation *op;
  Branching branching;
  Run edges;
};

// An edge: the successor it takes and the target that successor is, and
// the classes it passes, one per input of the target, a run of `passed`.
struct Edge {
  mlir::RegionSuccessor successor;
  TargetId target;
  Run passed;
};

// A successor of a region-branch op: a region it enters, or its own
// results. Its inputs (the region's arguments, the op's results), a run of
// `received`, are leaves of the graph, and the edges that enter it, a run
// of `entering`.
struct Target {
  std::optional<RegionId> region;
  Run inputs;
  Run entering;
};

// What the pass reads where the compiler is built and when it is made,
// never per function: each generated kind's op name, and each op's
// meaning, found once per pass instance by the class of op, which MLIR's
// open op set forces to be read at run time.
struct Kinds {
  // What the graph reads of an op of one class: the kind a pattern names it
  // by, its meaning, the operands its runtime function borrows, and, for a
  // guard, its decision.
  struct OfOp {
    std::optional<std::uint16_t> kind;
    std::optional<Meaning> meaning;
    Borrowed borrowed;
    std::optional<Decision> decision;
  };
  // By the op's TypeID, sorted, for the one lookup an op's class needs.
  std::vector<std::pair<mlir::TypeID, OfOp>> byTypeId;
  // By kind: a node a rule built names its op by its kind, and is computed
  // by its kind's meaning of a built node.
  std::vector<std::optional<mlir::RegisteredOperationName>> names;
  std::vector<std::optional<MeaningOfBuilt>> built;

  // The order the table is sorted in, a TypeID's address.
  static bool before(mlir::TypeID a, mlir::TypeID b) {
    return a.getAsOpaquePointer() < b.getAsOpaquePointer();
  }
  // Inline, so a skeleton rule that reads a guard's decision reaches the
  // table with no symbol of the engine's.
  OfOp of(mlir::TypeID id) const {
    auto it = llvm::lower_bound(
        byTypeId, id, [](const auto &entry, mlir::TypeID key) { return before(entry.first, key); });
    if (it == byTypeId.end() || it->first != id)
      return {};
    return it->second;
  }
  OfOp of(mlir::Operation *op) const { return of(op->getName().getTypeID()); }
};

// Every op's meaning the graph computes, by its TypeID (Values.cpp): each
// op the trait RuntimeFolds gives the one fold, its value instance; and
// each of upstream's ops on Doubles whose result IEEE 754 fixes (the
// generated ComputedOnDoubles), by the operation its own fold applies.
std::vector<std::pair<mlir::TypeID, Meaning>> meanings();

// Every op whose runtime function borrows a string or a big, by its TypeID
// (Values.cpp), read off its generated ABI row.
std::vector<std::pair<mlir::TypeID, Borrowed>> borrowings();

// Every guard op's decision, by its TypeID (Values.cpp): each op of the
// guard interface, its own `decide` at the graph's values.
std::vector<std::pair<mlir::TypeID, Decision>> decisions();

// What a constant an op of the input holds says of its value, read once
// from its attribute into the graph's own: an integer's interval, a
// Double, a string, or a big (an interval of one value in the small range,
// as the runtime holds it in its word; its cell past it, with the interval
// its sign gives); nothing for any other constant.
Facts heldFacts(mlir::Attribute value);

// What a constant the graph knows says of its value: the constant, and,
// for a big past the small range, the interval its sign gives.
Facts factsOf(const Constant &constant);

// The constant op of `value` at `type`, by `dialect`'s hook.
mlir::Value materialized(mlir::Dialect &dialect, mlir::RewriterBase &rewriter, mlir::Location loc,
                         mlir::Type type, mlir::Attribute value);

// A constant the graph knows, made where it is placed at `type`: its
// attribute, the one the graph makes, held by arith's constant or by
// `constants`', the dialect whose constant op holds a string's and a big's.
mlir::Value writeBack(mlir::RewriterBase &rewriter, mlir::Location loc, mlir::Type type,
                      const node::Integer &integer, mlir::Dialect &constants);
mlir::Value writeBack(mlir::RewriterBase &rewriter, mlir::Location loc, mlir::Type type,
                      const Constant &constant, mlir::Dialect &constants);

// A rule's variables as a match binds them, each to a class.
struct Bindings {
  llvm::SmallVector<std::optional<ClassId>, 4> vars;
};

// The pass's generated kinds, found once per pass instance (Rules.cpp).
Kinds makeKinds(mlir::MLIRContext *context);

// Which turn of a function's two: in the first every skeleton rule's edit
// stands; in the second a Rewrite is kept as it is (OperandFacts' header).
enum class Turn : std::uint8_t { First, Second };

// A function's e-graph holds at most this many nodes per op of its body, a
// constant of the specification, so the bytes its arena takes are known
// before its search starts, from the function alone: every run of the
// pass, whichever pass runs it, is admitted only while its arena fits
// beside the arenas in flight in the host's memory, so a small host
// compiles more slowly and never differently. Read from the generated
// tables, which Rules.cpp reads.
std::uint32_t nodesPerOp();

// The most operands any node a rule's right side builds has, read off the
// generated tables when the compiler is built: with the operands of the
// function's own ops, it bounds the operands the graph's keys hold.
std::uint32_t widestSide();

// The hash-cons's slot: a keyed node and the hash it was keyed under, kept
// so the table grows and deletes without hashing a node again.
struct Slot {
  std::optional<NodeId> node;
  std::uint32_t hash = 0;
};

// What one node costs the arena, every table it enters counted, a class
// counted with the node that made it, since each node is made with a class
// of its own: the node; its class; the class's slot in the union-find; the
// node's class and its next member; the hash-cons's two slots at half
// full; the union a class may owe the rebuild before it is paid, and its
// place on the rebuild's two lists of classes to repair; and extraction's
// chosen member and price.
inline constexpr std::uint64_t bytesPerNode =
    sizeof(Node) + sizeof(Class) + sizeof(ClassId) + sizeof(ClassId) +
    sizeof(std::optional<NodeId>) + 2 * sizeof(Slot) + sizeof(Owed) + 2 * sizeof(ClassId) +
    sizeof(std::optional<NodeId>) + sizeof(Cost);

// What one operand a node's key holds costs the arena: its class, and the
// use that puts the node on that class's users.
inline constexpr std::uint64_t bytesPerOperand = sizeof(ClassId) + sizeof(Use);

class Function {
public:
  Function(idr::FuncOp fn, const Kinds &kinds, const CalleeFacts *callees);

  // The bytes its arena may take, its budget's nodes, the most operands
  // their keys hold and the strings and bigs it may compute: known once it
  // is made, from the function alone, before its search starts.
  std::uint64_t arena() const {
    return budget * bytesPerNode + heldOperands * bytesPerOperand + constantBytes;
  }

  // The walk, then the rounds of the rules until saturation or the budget.
  void build();
  void extract();
  void decide(Turn turn);
  // The roots a rule decided a Rewrite of, with the rule and its choice,
  // region by region in walk order.
  struct Pending {
    mlir::Operation *root;
    std::uint32_t rule;
    Rewrite rewrite;
  };
  footprint::Vector<Pending> rewrites() const;
  static void rewriteSkeleton(const Pending &pending, mlir::RewriterBase &rewriter);
  void elaborate(mlir::RewriterBase &rewriter);

  // What the composite folds read of the graph as it is built: a class's
  // id, and the op of class `OpT` of the input a member of it is, one
  // computable wherever the class is used, with its operands' classes, or
  // the one the value a member keeps at another grade is built by.
  ClassId idOf(const Class &cls) const {
    return ClassId(static_cast<std::uint32_t>(&cls - classes.data()));
  }
  template <class OpT>
  std::optional<std::pair<OpT, llvm::SmallVector<ClassId, 4>>> builtOf(const Class &cls) const;

  // What a skeleton rule reads (OperandFacts), once the graph is settled.
  const Class &classOfValue(mlir::Value value) const;
  template <class OpT>
  OpT memberBuiltBy(mlir::Value value) const;
  std::optional<KnownConstant> knownOf(mlir::Value value) const;
  std::optional<Tag> constructorOf(mlir::Value value) const;
  mlir::Attribute heldBy(mlir::Value value) const;
  numeric::Known decisionOf(GuardOpInterface guard) const;
  Cost costOf(mlir::Value value) const;

  // What the function's e-graph did so far, the pass's work.
  std::uint64_t work() const { return steps; }

private:
  // Minting: a node and a class of its own, which holds what it says.
  NodeId make(Node node, Facts facts);
  RegionId newRegion(Region region);
  Node &at(NodeId n) { return nodes[n.index()]; }
  const Node &at(NodeId n) const { return nodes[n.index()]; }
  Class &at(ClassId c) { return classes[c.index()]; }
  const Class &at(ClassId c) const { return classes[c.index()]; }
  const Region &at(RegionId r) const { return regions[r.index()]; }
  std::span<const ClassId> childrenOf(const Node &node) const {
    return std::span<const ClassId>(children).subspan(node.children.first, node.children.count);
  }
  ClassId classOfNode(NodeId n) const { return nodeClass[n.index()]; }
  // The class of the value an op of the input keeps at another grade, its
  // first operand's root, where the op keeps its operand's value; none for
  // any other node. The one statement of a cast's value, which what a node
  // says (meant) and how a class is built (builtOf) each read.
  std::optional<ClassId> keptBy(const What &what, std::span<const ClassId> operands) const;

  // Building.
  ClassId leaf(mlir::Value value, RegionId home);
  // A constant an op holds as an attribute, read once into a value of the
  // graph's own, with the interval the op gives it, its class united with
  // the constant it is.
  ClassId held(mlir::Attribute value, mlir::Type type, mlir::Dialect *dialect,
               std::optional<mlir::ConstantIntRanges> interval);
  // The integer `value` of `type`; none where the type has no integer form,
  // or where a new node would pass the budget.
  std::optional<ClassId> integer(const llvm::APInt &value, mlir::Type type);
  // The constant `value` of `type`, which its constant op stands at; none
  // where a new node would pass the budget.
  std::optional<ClassId> known(const Constant &value, mlir::Type type);
  // Whether `facts` say a value of `type` is a constant its op stands at;
  // and that constant's class, made after the node's own run is given
  // back, none where they say none, or where a new node would pass the
  // budget.
  bool placeable(const Facts &facts, mlir::Type type) const;
  std::optional<ClassId> constantOf(const Facts &facts, mlir::Type type);
  // A node of the input that computes its value: the constant its meaning
  // gives, where that is placed; else its node, its class united with the
  // constant it is and with the argument its callee gives back, where it is
  // either.
  ClassId insert(node::Input op, mlir::Type type, std::span<const ClassId> operands);
  // A node a right side built; none once the budget is spent.
  std::optional<ClassId> insert(node::Built op, mlir::Type type,
                                std::span<const ClassId> operands);
  // `operands`' roots as a new run of `children`.
  Run childrenFor(std::span<const ClassId> operands);
  // The run last laid, for a node that is not made, given back.
  void unlay(Run run);
  // The interval upstream's transfer function gives an op of the input over
  // its operands' classes.
  std::optional<mlir::ConstantIntRanges> intervalOf(mlir::Operation *op,
                                                    std::span<const ClassId> operands) const;
  // The interval a node a right side built has over its operands' classes:
  // its kind's range function's (Rules.cpp).
  std::optional<mlir::ConstantIntRanges> intervalOf(const node::Built &op, mlir::Type type,
                                                    std::span<const ClassId> operands) const;
  // What a node's runtime meaning computes from its operands' classes,
  // where each is a constant; none where one is not, it has none, or it
  // does not admit them. A string or a big it computes past the bytes the
  // function's constants may take is dropped. A node that keeps its
  // operand's value computes nothing: it is the constant that operand is,
  // one the graph holds already, which takes no more of those bytes.
  std::optional<Facts> meant(const What &what, mlir::Type type,
                             std::span<const ClassId> operands);
  // What a node says of its value over its operands' facts as they are now:
  // its interval and what its meaning computes, met.
  Facts saysOf(NodeId n);
  // The argument `callee`, the function a floating call calls, gives back
  // whole as its result, where that is of the call's result's type.
  std::optional<ClassId> giveBack(solver::FunctionId callee, std::span<const ClassId> operands,
                                  mlir::Type type);
  // The class of the constant `callee` returns as its result `result` (the
  // callees' table, read from the constant op its final body returns),
  // where `call`'s result is of that constant's type; none where it returns
  // no constant there, or where a new node would pass the budget.
  std::optional<ClassId> returnedBy(solver::FunctionId callee, CallOp call, unsigned result);
  // A class whose facts are one constant holds that constant.
  void joinConstant(ClassId c);
  // The region a node can be computed in, from its operands' reaches; none
  // where they share none.
  std::optional<RegionId> needs(const Node &node) const;
  // The outer of two regions where one holds the other; none where neither
  // does.
  std::optional<RegionId> outerOf(RegionId a, RegionId b) const;

  // The union-find's choice of root and its refusals, and the rebuild that
  // restores congruence.
  const Facts &factsOf(ClassId c) const { return at(forest.rootOf(c)).facts; }
  Changed unite(ClassId a, ClassId b);
  // The contents `owed` moves to its root; the root.
  ClassId pay(const Owed &owed);
  void rebuild();
  void repair(ClassId c);
  // The holder's reach widened to where `member` can now be computed.
  Changed widen(ClassId holder, const Node &member);
  // Once the rounds are done, every reach at its fixpoint, and every class
  // and every value's class read at its root in one load.
  void settle();

  // The region graph (Regions.cpp): its branch points, their edges and the
  // targets they enter, read once off the walk's regions and skeleton.
  void connectRegions();
  // The first region of `owner`, an op whose regions `from` is, or is
  // nested in; none where no such op holds it.
  std::optional<RegionId> firstRegionOf(RegionId from, mlir::Operation *owner) const;
  // What the skeleton says of the values it gives, at the start of each
  // round (Regions.cpp): each region-branch op's successors' inputs, the
  // join of what the edges that may run pass them; each skeleton op's
  // results, its intervals over its operands'; and a guard's result, where
  // its condition holds, what its checked operand is.
  void skeletonSays();
  // The edges that may run, from the body and each region they enter, as
  // each point chooses over the constants its operands' classes hold.
  BitSet<EdgeId> runningEdges() const;
  // `said` met into the facts of `c`'s root; where they narrow, the class
  // unites with the constant they now say, and its users are read again at
  // the next rebuild.
  void narrow(ClassId c, const Facts &said);
  // The attribute an op of the input in `c`'s root class holds, from a
  // member; null where none does.
  mlir::Attribute heldIn(ClassId c) const;
  // Whether a member of `c`'s root class is a constant the write-back
  // places: an attribute an op held, an integer, or another constant.
  bool holdsConstant(ClassId c) const;

  // The rounds (Rules.cpp).
  void saturate();
  Changed round();
  // The first complete match of the rule's left side at `root`, its
  // conditions holding.
  std::optional<Bindings> matchAt(const table::Rule &rule, NodeId root) const;
  std::optional<ClassId> buildSide(const table::Rule &rule, const Bindings &bindings,
                                   std::uint32_t &at, mlir::Type type);
  bool holds(const table::Condition &condition, const Bindings &bindings) const;
  // The skeleton rules (Rules.cpp): the edit the first rule rooted at the
  // op decides, if one does.
  std::optional<Decided> decideSkeleton(mlir::Operation *op, const OperandFacts &facts) const;

  // The hash-cons, over every node but a leaf and an op with an identity:
  // each keyed once, by its kind, its payload and its operands as stored,
  // which the rebuild sets to their roots.
  std::optional<NodeId> lookup(const Node &node) const;
  void remember(NodeId n);
  void forget(NodeId n);
  static bool sameKey(const Node &a, std::span<const ClassId> ac, const Node &b,
                      std::span<const ClassId> bc);
  std::uint32_t hashOf(const Node &node) const;

  // Elaborating.
  bool visible(RegionId placed, RegionId scope) const;
  // Erases every floating op the written function no longer uses.
  void sweep(mlir::RewriterBase &rewriter);

  idr::FuncOp fn;
  const Kinds &kinds;
  const CalleeFacts *callees;
  std::uint64_t budget;
  // The most operands the graph's keys hold: an op of the input holds its
  // own, and a node a side builds at most the widest side's.
  std::uint64_t heldOperands;
  // The bytes of the runtime's memory the strings and bigs it computes may
  // take, as many as its nodes may; and those they take so far.
  std::uint64_t constantBytes;
  std::uint64_t computedBytes = 0;

  solver::Numbering<ValueTag> numbering;
  IndexVector<ValueId, std::optional<ClassId>> classOf;

  footprint::Vector<Node> nodes;
  footprint::Vector<ClassId> children;
  // By the operand's place in `children`.
  footprint::Vector<Use> uses;
  footprint::Vector<Class> classes;
  // The union-find over `classes`, which `unite` links by its own rule.
  solver::UnionFind<ClassId> forest;
  // By node: the class it was made with, which `find` takes to its root,
  // and the next member of the class it is in.
  footprint::Vector<ClassId> nodeClass;
  footprint::Vector<std::optional<NodeId>> nextMember;
  footprint::Vector<Region> regions;
  footprint::Vector<Skeletal> skeleton;

  // The region graph: the branch points, region by region; their edges,
  // point by point; the classes each edge passes; the targets; the classes
  // of their inputs, which receive what the edges pass; and the edges
  // entering each, target by target.
  footprint::Vector<Point> points;
  footprint::Vector<Edge> edges;
  footprint::Vector<ClassId> passed;
  footprint::Vector<Target> targets;
  footprint::Vector<ClassId> received;
  footprint::Vector<EdgeId> entering;

  // The unions the rebuild still owes, in the order they were made.
  footprint::Vector<Owed> owed;
  // The classes whose facts a rebuild narrowed or whose reach it moved,
  // whose users the next round's rebuild reads again.
  footprint::Vector<ClassId> carried;
  // Every union made: a round that made none and no node is the last.
  std::uint64_t unions = 0;

  // Open addressing with linear probing over node keys, grown by doubling
  // at half full, a key deleted by shifting back the run after it.
  footprint::Vector<Slot> slots;
  std::uint32_t filled = 0;

  // Extraction: each root's chosen member and its cost.
  footprint::Vector<std::optional<NodeId>> best;
  footprint::Vector<Cost> cost;

  // Each step of work, in the e-graph's own units: a node made, a rule
  // tried at a root, a meaning computed, a use a rebuild repaired, an
  // earlier op a repeated read is compared with and an op between them
  // read, a node an extraction pass prices, a placement an elaboration
  // looks at.
  std::uint64_t steps = 0;
};

} // namespace idr::egraph::detail

// What a skeleton rule reads, inline over the tables above.
#include "idr/Transforms/EGraph/Reads.h"

#endif // IDR_TRANSFORMS_EGRAPH_ENGINE_H
