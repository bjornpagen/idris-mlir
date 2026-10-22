// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One function's e-graph: its tables and its three phases.
//
// Build: one walk in walk order. Each op is classified by its declared
// effects: an op with none (an op-level acquisition only reports) floats,
// and is a node hash-consed into a class; an op whose only effect is the
// identity of its result is a node of its own, never merged, placed at
// most once per path; every other op, a region op, a call in tail
// position and a terminator stays in the skeleton of its region, in
// order, and so does an op whose value depends on its parent
// (DependsOnParent), which two parents would make two values. A node of
// the input is made with its analyses (an interval, by upstream's transfer
// function, whose one value, where it has one, is the integer it is; and,
// for a constant with no integer form, the op's own fold over the
// attributes its operands hold, never an op whose fold the compiling
// machine would compute) and the specification's rules rooted at its kind
// run at once, the first that matches replacing the node with its right
// side: every rule runs one way. A node a right side builds has no op to
// ask and none is made for it: its interval is its kind's range function
// over its operands' intervals, from the generated table, so one built
// over constants is its integer at once; it runs no rules. An integer is a
// value until the write-back makes its attribute. The class a node lands
// in, its own or the one that replaces it, meets what the node knows, so a
// rewrite loses no fact of the form it replaced.
// A class's members never change once made and its
// analyses only narrow, so no id goes stale and nothing is rebuilt: a
// node made over a class reads its analyses as they stood when it was
// made. A repeated read in a region with
// no write of what it reads between merges into the first, and a repeated
// op of the region's parent into the first; the skeleton rules decide
// their edits.
//
// Extract: each class's cheapest member, bottom-up in creation order,
// ties to the larger id.
//
// Elaborate: the regions in program order, each skeleton op's operands
// written back where they are demanded, a value placed in the scope that
// demands it unless an enclosing scope already holds it, the skeleton's
// edits carried out; then the input's floating ops, unused, are erased.
//
// Every id is minted by the table that holds it and never leaves the
// function; no map holds per-node state by an IR handle but the value
// numbering, which lives while the function is read; nothing recurses on
// the input: the walks are MLIR's and the placement's stack is explicit.
// Every table and stack sized by the function is the footprint's.
#ifndef IDR_TRANSFORMS_EGRAPH_ENGINE_H
#define IDR_TRANSFORMS_EGRAPH_ENGINE_H

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/EGraph.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

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
using NodeId = Id<NodeTag>;
using ClassId = Id<ClassTag>;
using RegionId = Id<RegionTag>;

// A run of one of the function's flat arrays.
struct Run {
  std::uint32_t first = 0, count = 0;
};

// Whether a node may stand for an equal one: a value with no identity is
// shared; one whose result takes a fresh identity is its own.
enum class Identity : std::uint8_t { Shared, Own };

// How the write-back writes an integer of a type: a word of the type, or
// every element of a shaped value of a static shape the same word, each
// arith's constant. A type whose integers have no constant op of their own
// at it has none, and an integer of it stays the op that computes it: a
// graded word, a numeral, and a big or a natural, whose constant op holds
// one only held static, which an integer the graph computes never is.
enum class IntegerForm : std::uint8_t { Word, Splat };
std::optional<IntegerForm> integerFormOf(mlir::Type type);

// What a node is.
namespace node {
// A value the e-graph does not see through: an argument of the function or
// of a region, or a result of a skeleton op.
struct Leaf {
  mlir::Value value;
};
// An op of the input, which stands for itself: its kind where a rule names
// it, and whether its result takes a fresh identity.
struct Input {
  mlir::Operation *origin;
  std::optional<std::uint16_t> kind;
  Identity identity;
};
// An op a rule's right side built: the op of its kind the write-back would
// make, of its type and the op's default properties. A rule makes nothing
// with an identity, so it is shared.
struct Built {
  std::uint16_t kind;
  mlir::RegisteredOperationName name;
};
// A constant held as an attribute: one an op of the input holds, or one a
// fold made where the constant has no integer form; materialized by
// `dialect`'s hook where it is placed.
struct Constant {
  mlir::Attribute value;
  mlir::Dialect *dialect;
};
// An integer the graph computed, by an interval of one value or a rule's
// literal: a value, made an attribute of `form` only where the write-back
// places it.
struct Integer {
  llvm::APInt value;
  IntegerForm form;
};
} // namespace node
using What = std::variant<node::Leaf, node::Input, node::Built, node::Constant, node::Integer>;

// A node that is no op: a leaf or a constant, of no operands. No table keys
// it, no node pattern matches it, and it costs nothing to place.
template <class N>
concept Atom = std::same_as<N, node::Leaf> || std::same_as<N, node::Constant> ||
               std::same_as<N, node::Integer>;

struct Node {
  What what;
  mlir::Type type;
  Run children;
};

// What the graph knows of a value, each where known: the interval an
// integer lies in, whose one value, where it has one, is the integer it is
// (the rule upstream's range optimizations use), so an integer constant is
// a value and never an attribute; and the constant as an attribute where an
// op already holds one, which the graph reads and never makes.
struct Facts {
  std::optional<mlir::ConstantIntRanges> range;
  mlir::Attribute attribute;

  std::optional<llvm::APInt> integer() const {
    return range ? range->getConstantValue() : std::nullopt;
  }
  // What is known of one value known two ways, both of which hold: it lies
  // in both intervals, and is either's attribute (two constants of one
  // value are one).
  void meet(const Facts &other);
};

struct Class {
  Run members;
  mlir::Type type;
  // What its node knew when the class was made, met with what each node
  // that landed in it since knew.
  Facts facts;
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
};

// Whether the graph asks an op's own fold: every op but those whose fold
// would compute on the compiling machine what the target computes.
enum class Folding : std::uint8_t { Folds, Never };

// What the pass reads where the compiler is built and when it is made,
// never per function: each generated kind's op name and the ops never
// folded, found once per pass instance, which MLIR's open op set forces to
// be read at run time.
struct Kinds {
  // (the op's TypeID, its kind), sorted by TypeID, for the one lookup an
  // Operation * needs.
  std::vector<std::pair<mlir::TypeID, std::uint16_t>> byTypeId;
  std::vector<std::optional<mlir::RegisteredOperationName>> names;
  // The TypeIDs of the ops never folded, sorted.
  std::vector<mlir::TypeID> neverFolded;

  std::optional<std::uint16_t> kindOf(mlir::Operation *op) const;
  Folding foldingOf(mlir::Operation *op) const;
};

// A rule's variables as a match binds them, each to a class.
struct Bindings {
  llvm::SmallVector<std::optional<ClassId>, 4> vars;
};

// The pass's generated kinds, found once per pass instance (Rules.cpp).
Kinds makeKinds(mlir::MLIRContext *context);

// Which round of a function's two: in the first every skeleton rule's edit
// stands; in the second a Rewrite is kept as it is (OperandFacts' header).
enum class Round : std::uint8_t { First, Second };

class Function {
public:
  Function(idr::FuncOp fn, const Kinds &kinds, const CalleeFacts *callees);

  void build();
  void extract();
  void decide(Round round);
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

  // What a skeleton rule reads (OperandFacts).
  const Class &classOfValue(mlir::Value value) const;
  mlir::Operation *originOf(mlir::Value value) const;
  Cost costOf(mlir::Value value) const;

  // What the function's e-graph did so far, the pass's work.
  std::uint64_t work() const { return steps; }

private:
  // Minting.
  NodeId newNode(Node node);
  ClassId newClass(Class cls);
  RegionId newRegion(Region region);
  Node &at(NodeId n) { return nodes[n.index()]; }
  const Node &at(NodeId n) const { return nodes[n.index()]; }
  Class &at(ClassId c) { return classes[c.index()]; }
  const Class &at(ClassId c) const { return classes[c.index()]; }
  const Region &at(RegionId r) const { return regions[r.index()]; }
  std::span<const ClassId> childrenOf(const Node &node) const {
    return std::span<const ClassId>(children).subspan(node.children.first, node.children.count);
  }
  std::span<const NodeId> membersOf(const Class &cls) const {
    return std::span<const NodeId>(members).subspan(cls.members.first, cls.members.count);
  }

  // Building.
  ClassId leaf(mlir::Value value);
  // A constant an op holds as an attribute, with the interval the op gives
  // it where it is an integer.
  ClassId constant(mlir::Attribute value, mlir::Type type, mlir::Dialect *dialect,
                   std::optional<mlir::ConstantIntRanges> interval);
  // The integer `value` of `type`; none where the type has no integer form.
  std::optional<ClassId> integer(const llvm::APInt &value, mlir::Type type);
  // A node of the input runs the rules rooted at its kind as it is made; a
  // node a right side built runs none, so one insertion applies rules once,
  // never recursively, and it is the one a spent budget refuses.
  ClassId insert(node::Input op, mlir::Type type, std::span<const ClassId> operands);
  std::optional<ClassId> insert(node::Built op, mlir::Type type,
                                std::span<const ClassId> operands);
  // `operands` as a new run of `children`.
  Run childrenFor(std::span<const ClassId> operands);
  // A class of its own for a node just made, holding what it knows.
  ClassId ownClass(NodeId made, mlir::Type type, Facts facts);
  ClassId alone(Node node, ClassId into);
  // What an op of the input computes over its operands' classes, and the
  // interval alone, which upstream's transfer function gives.
  Facts factsOf(mlir::Operation *op, std::span<const ClassId> operands) const;
  std::optional<mlir::ConstantIntRanges> intervalOf(mlir::Operation *op,
                                                    std::span<const ClassId> operands) const;
  // What a node a right side built computes over its operands' classes:
  // its kind's range function's interval (Rules.cpp).
  Facts factsOf(const node::Built &op, mlir::Type type, std::span<const ClassId> operands) const;
  std::optional<ClassId> giveBack(const node::Input &op, std::span<const ClassId> operands,
                                  mlir::Type type);
  // The rules rooted at the kind of `op`, just made as `made` (Rules.cpp):
  // the class of the right side of the first that matches, which the node
  // lands in; none when no rule matches.
  std::optional<ClassId> rewrite(NodeId made, const node::Input &op, mlir::Type type);
  std::optional<ClassId> buildSide(const table::Rule &rule, const Bindings &bindings,
                                   std::uint32_t &at, mlir::Type type);
  std::optional<std::uint32_t> matchClass(std::uint32_t at, ClassId cls, Bindings &bindings) const;
  std::optional<std::uint32_t> matchNode(std::uint32_t at, NodeId node, Bindings &bindings) const;
  bool holds(const table::Condition &condition, const Bindings &bindings) const;
  // The skeleton rules (Rules.cpp): the edit the first rule rooted at the
  // op decides, if one does.
  std::optional<Decided> decideSkeleton(mlir::Operation *op, const OperandFacts &facts) const;

  // The hash-cons.
  std::optional<ClassId> lookup(const Node &node) const;
  void remember(NodeId node, ClassId cls);
  static bool sameKey(const Node &a, std::span<const ClassId> ac, const Node &b,
                      std::span<const ClassId> bc);
  std::uint64_t hashOf(const Node &node, std::span<const ClassId> operands) const;

  // Elaborating.
  bool visible(RegionId placed, RegionId scope) const;
  // Erases every floating op the written function no longer uses.
  void sweep(mlir::RewriterBase &rewriter);

  idr::FuncOp fn;
  const Kinds &kinds;
  const CalleeFacts *callees;
  std::uint64_t budget;

  solver::Numbering<ValueTag> numbering;
  IndexVector<ValueId, std::optional<ClassId>> classOf;

  footprint::Vector<Node> nodes;
  footprint::Vector<ClassId> children;
  footprint::Vector<Class> classes;
  footprint::Vector<NodeId> members;
  footprint::Vector<Region> regions;
  footprint::Vector<Skeletal> skeleton;

  // Open addressing over node keys: each slot a node and its class, empty
  // when no node; grown by doubling at half full.
  struct Slot {
    std::optional<NodeId> node;
    std::optional<ClassId> cls;
  };
  footprint::Vector<Slot> slots;
  std::uint32_t filled = 0;

  // Extraction: each class's chosen member and its cost.
  footprint::Vector<std::optional<NodeId>> best;
  footprint::Vector<Cost> cost;

  // Each step of work, in the e-graph's own units: a node made, an earlier
  // op a repeated read is compared with and an op between them read, a
  // placement an elaboration looks at. Extraction reads each member once,
  // which its making counted.
  std::uint64_t steps = 0;
};

} // namespace idr::egraph::detail

#endif // IDR_TRANSFORMS_EGRAPH_ENGINE_H
