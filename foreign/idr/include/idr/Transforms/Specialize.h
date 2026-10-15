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
#include "idr/Analysis/Specialize.h"
#include "idr/Support/Actions.h"

#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <mutex>
#include <optional>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

namespace idr {

#define GEN_PASS_DECL_IDRREDIRECT
#define GEN_PASS_DECL_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"

class Holds;

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

namespace idr::specialize {

// A node: made once per key, by the first request of it. A SpecKeyAttr key
// makes a specialization, a KeyRaiseAttr key a raise.
struct Node {
  mlir::Attribute key;
  // The function it is cloned from.
  mlir::StringAttr owner;
  // From the key, known before the node is built.
  mlir::FlatSymbolRefAttr name;
  // Null until build.
  idr::FuncOp fn;
  // The binding time of each parameter, written by build: its owner's, by
  // its key, since its recursion goes where its owner's goes.
  llvm::SmallVector<BindingTime> times;
  // The nodes whose requests of the key were followed in the wave that made
  // the node, before it was in the program. With the node's own key they
  // are its request chain, which a key it requests may not grow. A
  // function the program held has no key and starts a chain.
  llvm::SmallVector<const Node *> parents;
};

// What the ready set tells the table. Both are safe from any worker.
class Schedule {
public:
  virtual ~Schedule() = default;
  // The function the program holds under `name`, or null: a node from the
  // insert that places it, between the wave that made it and the next.
  virtual idr::FuncOp lookup(mlir::StringAttr name) const = 0;
  // Whether no pass writes `fn` again: its component is final.
  virtual bool isFinal(idr::FuncOp fn) const = 0;
  // Whether the functions named `a` and `b`, both held by the program when
  // the run began, are one component of its call graph.
  virtual bool sameComponent(mlir::StringAttr a, mlir::StringAttr b) const = 0;
};

// The nodes of one run of idr-optimize, by key. The passes of the inner
// pipeline reach the table through their parent's cache, which hands out a
// const reference, so its state is behind a pointer that the const members
// write under one lock.
class Nodes {
public:
  // Empty; idr-optimize takes it with getAnalysis.
  Nodes(mlir::Operation *program, mlir::AnalysisManager &am);
  ~Nodes();
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Before the first task; the three outlive the run.
  void start(const Schedule &schedule, const BindingTimes &times, const Holds &holds) const;

  // The node `fn` is, or null.
  const Node *find(mlir::StringAttr fn) const;

  // The nodes `requester` asked for since the last take, each once, in the
  // order first asked, never the requester itself.
  llvm::SmallVector<Node *> takeRequests(idr::FuncOp requester) const;

  // True for exactly one caller per node: the one to build it.
  bool claim(Node &node) const;

  // The node's function, built detached from its owner's final body, and
  // its binding times. It requests nothing: its calls are redirected by its
  // own turns, once insert has placed it and its request chain is whole.
  // A failure is an internal error, emitted.
  mlir::LogicalResult build(Node &node) const;

  // Puts the built function into `program`: after its owner, then past
  // every node whose name sorts before its own. The ready set inserts every
  // node it built in a wave between that wave and the next, on the pass
  // thread: no worker reads the program's list of operations then, and no
  // request of the node's key is in flight.
  void insert(Node &node, idr::ProgramOp program) const;

  // The redirect step over `fn`: each call's key requested in walk order and
  // the call made a call of the key's node. `redirected` counts the
  // redirects, `changed` says whether anything changed. A failure is an
  // internal error, emitted.
  mlir::LogicalResult redirectCalls(idr::FuncOp fn, unsigned &redirected, bool &changed) const;

  struct State;

private:
  std::unique_ptr<State> state;
};

} // namespace idr::specialize

namespace idr::specialize::detail {

// The static shape of a value: what is known of it where it is built, over
// the runtime leaves it holds. A pattern is a hole (a runtime leaf), a
// constant, or a constructor over the patterns of its operands, a closure's
// included: after defunctionalization a closure is a constructor of its
// sum. A shape is taken once per argument of a call, with its leaves; the
// node is built from the key alone, each hole standing for the parameter
// that holds its leaf, so that what the key says and what the node computes
// cannot differ.
struct Pattern;

// A runtime leaf: which leaf of its key it is, counting the key's holes in
// order. How often the node may use it is its type's to say.
struct Hole {
  unsigned index;
};

struct Constant {
  mlir::Attribute value;
};

// A constructor, by its tag in the data type of the pattern's type.
struct Con {
  unsigned tag;
  std::vector<Pattern> fields;
};

// A value entered into a linear type (`idr.lin.enter`): the type of its
// position says so, and rebuilt it enters again.
struct Linear {
  // Exactly one: the pattern of the value that entered.
  std::vector<Pattern> value;
};

struct Pattern {
  std::variant<Hole, Constant, Con, Linear> node;
  mlir::Type type;

  bool isHole() const { return std::holds_alternative<Hole>(node); }
};

// The visitor of a pattern's node: one callable per case.
template <typename... Cases> struct Match : Cases... {
  using Cases::operator()...;
};

// One argument of a call: its pattern, whose holes are numbered from 0 and
// then among the key's, its runtime leaves in that order, and the binding
// time of its parameter.
struct Argument {
  Pattern pattern;
  llvm::SmallVector<mlir::Value> leaves;
  BindingTime time;
};

// A call's specialization key, composed over the patterns of its owner's
// parameters: the arguments, the value the call passes for each hole of
// the key, and for each argument the holes it fills.
struct Composed {
  llvm::SmallVector<Argument> args;
  SpecKeyAttr key;
  llvm::SmallVector<mlir::Value> values;
  llvm::SmallVector<llvm::SmallVector<unsigned>> held;
};

// The consumer of a call's result that raising moves into a node of the
// callee: the dispatch that is all its one use does with it. It is op
// handles, passed by value as ops are.
using Consumer = idr::Elimination;

// What one call wants: the key of its node, the function its key's
// patterns describe, and what the redirect to it takes.
struct Want {
  mlir::Attribute key;
  mlir::StringAttr owner;
  // The new call's operands: the leaves, or the call's operands and then
  // the consumer's free values.
  llvm::SmallVector<mlir::Value> operands;
  // A raise: the consumer the new call replaces.
  std::optional<Consumer> consumer;
};

// The forms of the consumers raising has met in one run, each printed
// once: a consumer that is, op for op, one met before has that one's form.
// Safe from any worker.
class Forms {
public:
  mlir::StringAttr formOf(mlir::OwningOpRef<idr::FuncOp> consumer);

private:
  std::mutex mutex;
  // Any value a hash takes is a key here.
  std::unordered_map<unsigned,
                     std::vector<std::pair<mlir::OwningOpRef<idr::FuncOp>, mlir::StringAttr>>>
      byHash;
};

// Patterns (Patterns.cpp).
Pattern leafOf(mlir::Value value, unsigned index);
Pattern shapeOf(mlir::Value value, llvm::SmallVectorImpl<mlir::Value> &leaves);
void renumber(Pattern &pattern, unsigned &next);
bool hasStructure(const Pattern &pattern);
bool isClosed(mlir::Value value);
bool usedOnce(mlir::Value value);
void eraseUnused(mlir::RewriterBase &rewriter, llvm::ArrayRef<mlir::Value> values);
// The value the key pattern `pattern` stands for at a position of `type`,
// rebuilt at `b` with location `loc`, hole i taken from `holes[i]`.
mlir::Value rebuild(mlir::OpBuilder &b, mlir::Location loc, mlir::Attribute pattern,
                    mlir::Type type, llvm::ArrayRef<mlir::Value> holes);
// The types of the holes of `pattern` at a position of `type`, in order.
void holeTypes(mlir::Attribute pattern, mlir::Type type, llvm::SmallVectorImpl<mlir::Type> &out);
// The number of holes of `pattern`.
unsigned countHoles(mlir::Attribute pattern);

// Keys (Keys.cpp). `own` is the callee's spec key when the callee is a
// specialization node; `seen` is the binding time of each of the callee's
// parameters as the call sees them: the callee's own when the call stays
// within the recursion of the component its requester stands for, free for
// each when it enters that component from outside.
mlir::Attribute keyOf(const Pattern &pattern);
std::optional<Composed> composeKey(idr::CallOp call, SpecKeyAttr own,
                                   llvm::ArrayRef<BindingTime> seen);

// The order a key is compared by with the keys on its request chain. It
// remembers the size of each constant it measured; one per run, under the
// table's lock.
class Order {
public:
  // Whether `key` grows `ancestor`: both are spec keys of one owner, and
  // `ancestor` embeds in `key` but `key` does not embed in `ancestor`.
  bool grows(mlir::Attribute ancestor, mlir::Attribute key);

private:
  using Embeddings = llvm::DenseMap<std::pair<mlir::Attribute, mlir::Attribute>, bool>;
  bool embeds(mlir::Attribute small, mlir::Attribute big, Embeddings &known);
  bool atMost(mlir::Attribute small, mlir::Attribute big);
  llvm::APInt size(mlir::Attribute constant);

  llvm::DenseMap<mlir::Attribute, llvm::APInt> sizes;
};

// Raising (Consumer.cpp). `callee` is the call's callee, final.
std::optional<Consumer> consumerOf(idr::CallOp call, idr::FuncOp callee, const Holds &holds);
// The consumer as a detached function of the call's result and its free
// values, which are appended to `free`.
mlir::OwningOpRef<idr::FuncOp> consumerFunction(idr::CallOp call, const Consumer &consumer,
                                                llvm::SmallVectorImpl<mlir::Value> &free);
// The one decision on a call in a function that is `requester` (the node it
// is, or null): its raise key, else its spec key, else none. `callee` is the
// call's callee, final, `calleeNode` the node it is, or null, and `seen` as
// composeKey takes it.
std::optional<Want> decide(idr::CallOp call, const Node *requester, idr::FuncOp callee,
                           const Node *calleeNode, llvm::ArrayRef<BindingTime> seen,
                           const Holds &holds, Forms &forms);

// The nodes' bodies (Specialization.cpp, Raise.cpp), from the owner's final
// function, detached.
mlir::FailureOr<idr::FuncOp> buildSpec(idr::FuncOp owner, SpecKeyAttr key, mlir::StringAttr name);
mlir::FailureOr<idr::FuncOp> buildRaise(idr::FuncOp owner, KeyRaiseAttr key,
                                        mlir::StringAttr name);

// Calling a node (Redirect.cpp): `call`, and a raise's consumer, become a
// call of `target` with `want`'s operands.
idr::CallOp redirect(mlir::RewriterBase &rewriter, idr::CallOp call,
                     mlir::FlatSymbolRefAttr target, const Want &want);

} // namespace idr::specialize::detail

#endif // IDR_TRANSFORMS_SPECIALIZE_H
