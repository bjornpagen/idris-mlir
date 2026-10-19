// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Specialization as nodes of idr-optimize's ready set: the table of nodes
// by key, each made once by the first call that requests it and built from
// its key and its owner's final body; idr-redirect, the inner pipeline's
// step that requests each call's key and calls its node; idr-binding-times,
// which reports what a call may specialize on. What the units share is in
// idr::specialize::detail.
#ifndef IDR_TRANSFORMS_SPECIALIZE_H
#define IDR_TRANSFORMS_SPECIALIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/BindingTimes.h"
#include "idr/Support/Actions.h"

#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <mutex>
#include <optional>
#include <unordered_map>
#include <utility>
#include <variant>

namespace idr {

#define GEN_PASS_DECL_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"

// idr-redirect calls a raise node: the call and its consumer become one
// call. Performed on idr-optimize's workers, which run one after another
// while the context has an action handler.
struct RaiseAction : support::TaggedAction<RaiseAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-raise";
};

// idr-redirect calls a specialization node.
struct SpecializeCloneAction : support::TaggedAction<SpecializeCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
};

} // namespace idr

namespace idr::optimize {
class Node;
} // namespace idr::optimize

namespace idr::specialize {

// What a node is made from: a specialization's key, or a raise's. Each is
// the uniqued attribute it is, so the table's memos key on its identity.
using Key = std::variant<SpecKeyAttr, KeyRaiseAttr>;
using RaiseKey = std::variant_alternative_t<1, Key>;

// A key as the attribute it is, which uniques it.
inline mlir::Attribute attributeOf(const Key &key) {
  return std::visit([](auto attr) -> mlir::Attribute { return attr; }, key);
}

// The function a node is cloned from, which its key names: a spec key's
// origin, a raise key's callee.
inline mlir::StringAttr ownerOf(const Key &key) {
  return std::visit(llvm::makeVisitor([](SpecKeyAttr spec) { return spec.getOrigin(); },
                                      [](RaiseKey raise) { return raise.getCallee(); }),
                    key);
}

// A node's phases, each holding what it has: asked for by a request and
// not yet built; claimed by the one worker that builds it; built, detached,
// with the binding time of each parameter (its owner's, by its key, since
// its recursion goes where its owner's goes); placed in the program, as
// the ready set's node it became.
struct Requested {};
struct Claimed {};
struct Built {
  idr::FuncOp fn;
  llvm::SmallVector<BindingTime> times;
};
struct Placed {
  optimize::Node *node;
};

// A node: made once per key, by the first request of it.
struct Node {
  Key key;
  // The function the program held that it stands for: its owner's origin,
  // back to a function the program held, fixed when it is made.
  mlir::StringAttr origin;
  // From the key, known before the node is built.
  mlir::FlatSymbolRefAttr name;
  // The nodes whose requests of the key were followed in the wave that made
  // the node, before it was in the program. With the node's own key they
  // are its request chain, which a key it requests may not grow. A
  // function the program held has no key and starts a chain.
  llvm::SmallVector<const Node *> parents;
  // Changed only under the table's lock.
  std::variant<Requested, Claimed, Built, Placed> state;
  // Whether a request of it passed a closure something else uses too
  // (sharesClosure). Set under the table's lock.
  bool sharedClosure = false;
};

// A callee whose component is final: its function and the binding time of
// each of its parameters, which no longer change.
struct FinalCallee {
  idr::FuncOp fn;
  llvm::ArrayRef<BindingTime> times;
};

// What the ready set tells the table. Each is safe from any worker: the
// ready set changes only between waves.
class Schedule {
public:
  virtual ~Schedule() = default;
  // The ready set's node of the function the program holds under `name`:
  // one it held when the run began, or a node placed between two waves;
  // null for none.
  virtual optimize::Node *held(mlir::StringAttr name) const = 0;
  // The function the program holds under `name`, a function of the
  // program, once its component is final and nothing writes it again;
  // nothing before.
  virtual std::optional<FinalCallee> finalCallee(mlir::StringAttr name) const = 0;
  // Whether the functions named `a` and `b`, both held by the program when
  // the run began, are one component of its call graph.
  virtual bool sameComponent(mlir::StringAttr a, mlir::StringAttr b) const = 0;
};

// The nodes of one run of idr-optimize, by key. Every worker's redirect
// step and the scheduler share it, each through a const reference, so its
// state is behind a pointer that the const members write under one lock.
class Nodes {
public:
  // Empty, for one run of idr-optimize whose ready set is `schedule`, which
  // outlives the table.
  explicit Nodes(const Schedule &schedule);
  ~Nodes();

  // The node `fn` is, or null: a function the program held is none.
  const Node *find(mlir::StringAttr fn) const;

  // The nodes `requester` was given since the last take, in name order:
  // each once ever, never the requester itself. Every request of the
  // requester is judged against the keys it was given before, so it is
  // given finitely many and its takes end.
  llvm::SmallVector<Node *> takeRequests(idr::FuncOp requester) const;

  // True for exactly one caller per node, the one to build it: the node
  // goes from requested to claimed.
  bool claim(Node &node) const;

  // The node's function, built detached from its owner's final body, and
  // its binding times: the node goes from claimed to built. It requests
  // nothing: its calls are redirected by its own turns, once insert has
  // placed it and its request chain is whole. A failure is an internal
  // error, emitted.
  mlir::LogicalResult build(Node &node) const;

  // Puts the built function into `program`, after its owner and past every
  // node whose name sorts before its own, and the node goes from built to
  // placed as `made`, the ready set's node made from what it built. The
  // ready set places every node built in a wave between that wave and the
  // next, on the pass thread: no worker reads the program's list of
  // operations then, and no request of the node's key is in flight.
  void insert(Node &node, idr::ProgramOp program, optimize::Node &made) const;

  // Whether a call of `node` reads a final callee: it is placed and its
  // component final.
  bool ready(const Node &node) const;

  // The redirect step over `fn`: each call's key requested in walk order and
  // the call made a call of the key's node; how many calls it redirected.
  // A failure is an internal error, emitted.
  mlir::FailureOr<unsigned> redirectCalls(idr::FuncOp fn) const;

  struct State;

private:
  std::unique_ptr<State> state;
};

} // namespace idr::specialize

namespace idr::optimize {

// idr-redirect, a step of idr-optimize's inner pipeline (InnerPasses.td),
// for one run: it requests each call's key from `nodes` and calls its node,
// and counts the calls it redirects into `redirected`.
std::unique_ptr<mlir::Pass> createRedirect(const specialize::Nodes &nodes,
                                           mlir::Pass::Statistic &redirected);

} // namespace idr::optimize

namespace idr::specialize::detail {

// The static shape of a value is a key attribute: what is known of it where
// it is built, over the runtime leaves it holds. A pattern is a hole
// (#idr.key_hole, a runtime leaf), a constant, or a constructor
// (#idr.key_con) over the patterns of its operands, a closure's included:
// after defunctionalization a closure is a constructor of its sum. A hole
// has no number: the i-th hole of a key, in pre-order over its patterns,
// is the node's parameter i, and the i-th leaf of a call. A shape is taken
// once per argument of a call, with its leaves; the node is built from the
// key alone, each hole standing for the parameter that holds its leaf, so
// that what the key says and what the node computes cannot differ.

// A call's specialization key, composed over the patterns of its owner's
// parameters, and the value the call passes for each hole of the key.
struct Composed {
  SpecKeyAttr key;
  llvm::SmallVector<mlir::Value> values;
};

// The consumer of a call's result that raising moves into a node of the
// callee: the dispatch that is all its one use does with it. It is op
// handles, passed by value as ops are.
using Consumer = idr::Elimination;

// What one call wants, by kind: a specialization's key and the leaves the
// call passes for its holes; or a raise's key, the consumer the new call
// replaces, and its operands, the call's and then the consumer's free
// values.
struct SpecWant {
  SpecKeyAttr key;
  llvm::SmallVector<mlir::Value> leaves;
};
struct RaiseWant {
  RaiseKey key;
  Consumer consumer;
  llvm::SmallVector<mlir::Value> operands;
};
using Want = std::variant<SpecWant, RaiseWant>;

// The run's table of the consumer forms raising has met: each a detached
// idr.func, interned by what idr-deduplicate compares, so a consumer that
// is, op for op, one met before has that one's form, and named by the
// digest of its canonical text, printed once. A raise key holds its form by
// that name, a uniqued attribute, and the build reads the consumer back
// from here by it. Safe from any worker; the forms are never written once
// interned, so several workers may read one.
class Forms {
public:
  // The form of `consumer`: the form of one interned before that is it, or
  // a new one. A new consumer whose digest another form holds is an
  // internal error at `at`.
  mlir::FailureOr<mlir::StringAttr> intern(mlir::Location at,
                                           mlir::OwningOpRef<idr::FuncOp> consumer);
  // The consumer interned as `form`, one intern gave.
  idr::FuncOp at(mlir::StringAttr form) const;

private:
  mutable std::mutex mutex;
  // The forms of each hash, in the order met. Any value a hash takes is a
  // key here.
  std::unordered_map<unsigned, llvm::SmallVector<mlir::StringAttr, 1>> byHash;
  llvm::DenseMap<mlir::StringAttr, mlir::OwningOpRef<idr::FuncOp>> byForm;
};

// Patterns (Patterns.cpp).
// The pattern of `value`, its leaves appended to `leaves` in pre-order.
mlir::Attribute shapeOf(mlir::Value value, llvm::SmallVectorImpl<mlir::Value> &leaves);
// Whether a pattern has structure: a constructor, as a node or as a
// constant. A lone scalar is none: a number specialized on would make a
// node per value, where LLVM weighs constant arguments better.
bool hasStructure(mlir::Attribute pattern);
bool isClosed(mlir::Value value);
bool usedOnce(mlir::Value value);
void eraseUnused(mlir::RewriterBase &rewriter, llvm::ArrayRef<mlir::Value> values);
// The value the key pattern `pattern` stands for at a position of `type`,
// rebuilt at `b` with location `loc`, each hole it meets taken from
// `holes[next++]`.
mlir::Value rebuild(mlir::OpBuilder &b, mlir::Location loc, mlir::Attribute pattern,
                    mlir::Type type, llvm::ArrayRef<mlir::Value> holes, unsigned &next);
// The types of the holes of `pattern` at a position of `type`, in order.
void holeTypes(mlir::Attribute pattern, mlir::Type type, llvm::SmallVectorImpl<mlir::Type> &out);
// The number of holes of `pattern`.
unsigned countHoles(mlir::Attribute pattern);

// Keys (Keys.cpp). `own` is the callee's spec key when the callee is a
// specialization node; `seen` is the binding time of each of the callee's
// parameters as the call sees them: the callee's own when the call stays
// within the recursion of the component its requester stands for, fixed
// for each when it enters that component from outside.
std::optional<Composed> composeKey(idr::CallOp call, std::optional<SpecKeyAttr> own,
                                   llvm::ArrayRef<BindingTime> seen);

// What `key`, a key over parameters of types `params`, fixes when it fixes
// closures alone: the labels of those closures (constructors of the sums
// defunctionalization made, their captures included); none when it fixes
// a parameter that holds no closure, or a structure a recursion could walk
// is among them: a constructor of another data type, or a closure that
// captures, at any depth, a closure of its own label. A node of a
// key that fixes closures alone applies them: its body is their code run
// on what they carry.
std::optional<llvm::SmallVector<mlir::StringAttr>> closuresFixed(SpecKeyAttr key,
                                                                 mlir::TypeRange params);
// Whether `call` passes a closure, or a closure or suspension it captures,
// that something else uses too: a node it asks for that fixes the closure
// copies its code wherever it is inlined, where applying the closure once
// would consume it.
bool sharesClosure(idr::CallOp call);

// The order a key is compared by with the keys on its request chain and
// the keys its requester was given. It remembers the size of each constant
// it measured; one per run, under the table's lock.
class Order {
public:
  // Whether `key` grows `ancestor`, two spec keys of one owner: `ancestor`
  // embeds in `key` but `key` does not embed in `ancestor`.
  bool grows(SpecKeyAttr ancestor, SpecKeyAttr key);

private:
  using Embeddings = llvm::DenseMap<std::pair<mlir::Attribute, mlir::Attribute>, bool>;
  bool embeds(mlir::Attribute small, mlir::Attribute big, Embeddings &known);
  bool atMost(mlir::Attribute small, mlir::Attribute big);
  llvm::APInt size(mlir::Attribute constant);

  llvm::DenseMap<mlir::Attribute, llvm::APInt> sizes;
};

// Where the operand of a hole of a lifted key comes from: the operand of a
// hole of the key it was lifted from, or a scalar or run lifted out of that
// key, built at the call at its hole's type.
struct Kept {
  unsigned hole;
};
struct Lifted {
  mlir::Attribute constant;
};
using Source = std::variant<Kept, Lifted>;

// Whether two spec keys of one owner are one shape: holes, constructors and
// runs where the other has them, and scalars of one kind, whatever their
// values.
bool sameShape(SpecKeyAttr a, SpecKeyAttr b);
// `key` with each scalar where it differs from `earlier`, a key of its
// shape, lifted out into a hole, `sources` saying for each hole of the
// result, in order, where its operand comes from: a hole of `key` or a
// constant lifted out.
SpecKeyAttr lift(SpecKeyAttr earlier, SpecKeyAttr key, llvm::SmallVectorImpl<Source> &sources);

// Raising (Consumer.cpp). What a call may do is the call's own effects.
std::optional<Consumer> consumerOf(idr::CallOp call);
// The consumer as a detached function of the call's result and its free
// values, which are appended to `free`.
mlir::OwningOpRef<idr::FuncOp> consumerFunction(idr::CallOp call, const Consumer &consumer,
                                                llvm::SmallVectorImpl<mlir::Value> &free);
// The one decision on a call in a function that is `requester` (the node it
// is, or null): its raise key, else its spec key, else none. `callee` is the
// call's callee, final, `calleeNode` the node it is, or null, and `seen` as
// composeKey takes it. A failure is an internal error of `forms`, emitted.
mlir::FailureOr<std::optional<Want>> decide(idr::CallOp call, const Node *requester,
                                            idr::FuncOp callee, const Node *calleeNode,
                                            llvm::ArrayRef<BindingTime> seen, Forms &forms);

// The nodes' bodies (Specialization.cpp, Raise.cpp), from the owner's final
// function, detached. A raise node's consumer is its key's form in `forms`.
mlir::FailureOr<idr::FuncOp> buildSpec(idr::FuncOp owner, SpecKeyAttr key, mlir::StringAttr name);
idr::FuncOp buildRaise(idr::FuncOp callee, RaiseKey key, mlir::StringAttr name,
                       const Forms &forms);

// Calling a node (Redirect.cpp). The operands of a call of the node whose
// key is `key`: for each of its holes, as `sources` says, the leaf of
// `want` it kept, or the constant lifted out of it, built before `call` at
// the hole's type, which is the node's parameter's.
llvm::SmallVector<mlir::Value> operandsOf(mlir::RewriterBase &rewriter, idr::CallOp call,
                                          const SpecWant &want, SpecKeyAttr key,
                                          llvm::ArrayRef<Source> sources,
                                          const Schedule &schedule);
// `call` becomes a call of `target`, a specialization node, with
// `operands`.
idr::CallOp redirect(mlir::RewriterBase &rewriter, idr::CallOp call,
                     mlir::FlatSymbolRefAttr target, llvm::ArrayRef<mlir::Value> operands);
// `call` and the consumer `want` raises become a call of `target`, a raise
// node, with `want`'s operands.
idr::CallOp redirect(mlir::RewriterBase &rewriter, idr::CallOp call,
                     mlir::FlatSymbolRefAttr target, const RaiseWant &want);

} // namespace idr::specialize::detail

#endif // IDR_TRANSFORMS_SPECIALIZE_H
