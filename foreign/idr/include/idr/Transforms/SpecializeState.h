// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize: each key's node and its phases,
// the consumer forms raising met, what each requester was given, and the
// table the workers share, with the state behind its pointer, which the
// nodes' phases (Specialize.cpp) read and write under its lock.
#ifndef IDR_TRANSFORMS_SPECIALIZESTATE_H
#define IDR_TRANSFORMS_SPECIALIZESTATE_H

#include "idr/Support/Footprint.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/OwningOpRef.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/xxhash.h"

#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <variant>

namespace idr::optimize {
class Schedule;
} // namespace idr::optimize

namespace idr::specialize {

//===----------------------------------------------------------------------===//
// The nodes of one run
//===----------------------------------------------------------------------===//

// A node's phases, each holding what it has: asked for and not built;
// claimed by the one worker that builds it; built, detached, with its
// parameters' binding times; placed in the program as the function the
// schedule numbered.
struct Requested {};
struct Claimed {};
struct Built {
  FuncOp fn;
  llvm::SmallVector<BindingTime> times;
};
struct Placed {
  FunctionId id;
};
using Phase = std::variant<Requested, Claimed, Built, Placed>;

struct Node {
  Key key;
  // What inlining the copy does to the recursion its origin is on, the
  // function's own `copy` once the run ends: a step of a recursion on
  // static data, whose next step is another copy, so inlining it would
  // unroll the recursion into its callers; or a beta step, whose key fixes
  // closures alone, of labels outside the origin's component and none of
  // them shared, so inlined it consumes the constructors its caller built
  // and calls the recursion, never itself. None for a raise, a signature
  // copy, or a pattern copy of an origin on no cycle, which the inline
  // verdict weighs as any function. Decided when the key is granted; a
  // later request that shares a closure makes a beta step a step, and
  // nothing makes a step anything else.
  std::optional<CopyKind> copy;
  // The function the program held that it stands for, back through the
  // copies it was made from.
  FunctionId origin;
  mlir::FlatSymbolRefAttr name;
  // The nodes whose requests made it in the wave it was made, a set: the
  // keys on a request chain are read as a set, and its order is never.
  llvm::SmallVector<const Node *> parents;
  Phase phase = Requested{};
};

// The consumer forms raising has met: each a detached function, interned
// by upstream's structural equivalence (idr-deduplicate's) and known by
// the digest of its structure, which names the raise copies of it. The
// number a form gets is the order workers met it in, so nothing outside
// this table reads it: a name reads the digest. Safe from any worker; a
// form is never written once interned.
class Forms {
public:
  FormId intern(mlir::OwningOpRef<FuncOp> consumer);
  FuncOp at(FormId form) const;
  llvm::XXH128_hash_t digestOf(FormId form) const;

private:
  struct Form {
    mlir::OwningOpRef<FuncOp> fn;
    llvm::XXH128_hash_t digest;
  };
  mutable std::mutex mutex;
  llvm::DenseMap<std::uint64_t, llvm::SmallVector<FormId, 1>> byDigest;
  footprint::Vector<Form> forms;
};

// What a requester asked for: the keys it was given, by owner, against
// which every key of that owner it asks for later is judged, and the nodes
// it has not taken yet. Held by the requester's turn, which one worker
// owns, so judging a request takes no lock.
class Requester {
public:
  llvm::ArrayRef<const PatternKey *> given(FunctionId owner) const;
  void give(Node &node);
  // The nodes given since the last take, in name order, each once.
  llvm::SmallVector<Node *> take();

private:
  llvm::SmallVector<std::pair<FunctionId, llvm::SmallVector<const PatternKey *, 2>>, 4> keys;
  llvm::SmallVector<Node *> waiting;
};

// What one call asks for.
struct PatternWant {
  const PatternKey *key;
  llvm::SmallVector<mlir::Value> leaves;
};
struct RaiseWant {
  const RaiseKey *key;
  Elimination consumer;
  llvm::SmallVector<mlir::Value> operands;
};
struct SignatureWant {
  const SignatureKey *key;
};
using Want = std::variant<PatternWant, RaiseWant, SignatureWant>;

// The table of one run: every node by key, the arena, the forms. Workers
// share it; a node is inserted and its phase moved under the lock, and
// nothing else is.
class Nodes {
public:
  explicit Nodes(const optimize::Schedule &schedule);
  ~Nodes();

  Arena &arena() { return keys; }
  Forms &forms() { return consumers; }

  // The node `fn` is, or null for a function the program held.
  const Node *find(FunctionId fn) const;

  // The node `want`'s key names for `requester`, judged on its own state
  // and made if new; none where the key grows one given before, or a lift
  // leaves no structure: the call stays a call. A name another key holds
  // is an internal error, emitted at `at`.
  struct Grant {
    Node *node;
    const PatternKey *key;
    llvm::SmallVector<Source> sources;
  };
  mlir::FailureOr<std::optional<Grant>> request(FunctionId requester, Requester &state,
                                                const Want &want, mlir::Operation *at);

  // True for exactly one caller per node: it goes from requested to
  // claimed.
  bool claim(Node &node);
  // The node's function, built detached from its owner as the schedule
  // lets `claimant` read it: it goes from claimed to built.
  mlir::LogicalResult build(Node &node, FunctionId claimant);
  // The node, built, was numbered by the schedule as `id`.
  void place(Node &node, FunctionId id);
  bool placed(const Node &node) const;
  // Once no turn runs: each placed copy's kind written on its function,
  // where the inline verdict reads it after the run.
  void writeCopies();

private:
  struct State;
  std::unique_ptr<State> state;
  Arena keys;
  Forms consumers;
};

// idr-redirect, a step of idr-optimize's inner pipeline: each call whose
// arguments compose a key, or whose result a dispatch consumes, requests
// its node and calls it.
std::unique_ptr<mlir::Pass> createRedirect(optimize::Schedule &schedule, Nodes &nodes,
                                           mlir::Pass::Statistic &redirected);

struct Nodes::State {
  explicit State(const optimize::Schedule &schedule) : schedule(schedule) {}

  // Held while a node is inserted or its phase moves, and nowhere else: a
  // request is judged on its requester's own state, which its turn owns.
  std::mutex mutex;
  const optimize::Schedule &schedule;
  // Every node, in the order made, each where it was made for the run's
  // life, in the footprint's storage; and by its key's identity in the
  // arena.
  std::deque<Node, footprint::Allocator<Node>> nodes;
  llvm::DenseMap<const void *, Node *> byKey;
  // Each name a key took, to its node: a second key on one name is the
  // compiler's error, and a name the program held when the run began is a
  // copy an earlier run made of the same key.
  llvm::DenseMap<mlir::StringAttr, Node *> byName;
  // The node each placed function is, by its id, null for a function the
  // program held. It grows as copies are placed, each at the next id the
  // graph's editor minted, so an id past its end is a function no node is
  // yet.
  footprint::Vector<Node *> byFunction;

  void placeAt(FunctionId id, Node &node) {
    if (byFunction.size() <= id.index())
      byFunction.resize(id.index() + 1, nullptr);
    byFunction[id.index()] = &node;
  }
  Node *placedAt(FunctionId id) const {
    return id.index() < byFunction.size() ? byFunction[id.index()] : nullptr;
  }
};

} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZESTATE_H
