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
// (DependsOnParent), which two parents would make two values. A node is
// made with its classes' analyses (a constant, by the op's fold with
// constant operands only; an interval, by upstream's transfer functions)
// and the specification's rules rooted at its kind run at once, each right
// side built the same way: Simplify replaces the node's class, Equal makes
// a new class of both. A class never changes once made, so no id goes
// stale and nothing is rebuilt. A repeated read in a region with no write
// of what it reads between merges into the first, and a repeated op of the
// region's parent into the first; the skeleton rules decide their edits.
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
#include "idr/Transforms/EGraph.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

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

// What a node is.
namespace node {
// A value the e-graph does not see through: an argument of the function or
// of a region, or a result of a skeleton op.
struct Leaf {
  mlir::Value value;
};
// An op: of the input (its origin), or made by a rule (no origin, its
// properties the op's defaults).
struct Op {
  mlir::OperationName name;
  std::optional<std::uint16_t> kind;
  mlir::Operation *origin;
  Identity identity;
};
// A constant, materialized by `dialect`'s hook where it is placed.
struct Constant {
  mlir::Attribute value;
  mlir::Dialect *dialect;
};
} // namespace node
using What = std::variant<node::Leaf, node::Op, node::Constant>;

struct Node {
  What what;
  mlir::Type type;
  Run children;
};

struct Class {
  Run members;
  mlir::Type type;
  // The analyses, each computed once, when the class is made.
  mlir::Attribute constant;
  std::optional<mlir::ConstantIntRanges> range;
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

// What the pass reads where the compiler is built and when it is made,
// never per function: each generated kind's op name, found once per pass
// instance, which MLIR's open op set forces to be read at run time.
struct Kinds {
  // (the op's TypeID, its kind), sorted by TypeID, for the one lookup an
  // Operation * needs.
  std::vector<std::pair<mlir::TypeID, std::uint16_t>> byTypeId;
  std::vector<std::optional<mlir::RegisteredOperationName>> names;

  std::optional<std::uint16_t> kindOf(mlir::Operation *op) const;
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
  ClassId constant(mlir::Attribute value, mlir::Type type, mlir::Dialect *dialect);
  // Whether a node's insertion runs the rules: a node of the input does; a
  // node a rule's right side made does not, so one insertion applies rules
  // once, never recursively.
  enum class Rules : std::uint8_t { Run, Skip };
  std::optional<ClassId> insert(mlir::OperationName name, std::optional<std::uint16_t> kind,
                                mlir::Operation *origin, Identity identity, mlir::Type type,
                                std::span<const ClassId> operands, Rules rules);
  ClassId alone(Node node, ClassId into);
  void analyse(Class &cls, const Node &node);
  std::optional<ClassId> giveBack(const node::Op &op, std::span<const ClassId> operands,
                                  mlir::Type type);
  // The rules rooted at a node's kind (Rules.cpp): the first that matches
  // either replaces the node's class or joins the node to its right side.
  struct NoRule {};
  struct Replace {
    ClassId by;
  };
  struct Join {
    ClassId with;
  };
  using Rewritten = std::variant<NoRule, Replace, Join>;
  Rewritten rewrite(NodeId made, const Class &analysed);
  std::optional<ClassId> buildSide(const table::Rule &rule, const Bindings &bindings,
                                   std::uint32_t &at, mlir::Type type, mlir::Dialect *dialect);
  std::optional<std::uint32_t> matchClass(std::uint32_t at, ClassId cls, Bindings &bindings) const;
  std::optional<std::uint32_t> matchNode(std::uint32_t at, NodeId node, Bindings &bindings) const;
  bool holds(const table::Condition &condition, const Bindings &bindings) const;
  // The skeleton rules (Rules.cpp): the edit the first rule rooted at the
  // op decides.
  Fate decideSkeleton(mlir::Operation *op, const OperandFacts &facts) const;

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

  // Each step of work, in the e-graph's own units: a node made, a member a
  // join copies, an earlier op a repeated read is compared with and an op
  // between them read, a placement an elaboration looks at. Extraction
  // reads each member once, which its making counted.
  std::uint64_t steps = 0;
};

} // namespace idr::egraph::detail

#endif // IDR_TRANSFORMS_EGRAPH_ENGINE_H
