// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize: each key's node and its phases,
// the consumer forms raising met, what each requester asked for, and the
// table of nodes, with the state behind its pointer (Specialize.cpp). The
// table is written on the pass thread between waves alone and only read
// while the turns run, so no lock guards it and the order turns ask in
// reaches no node.
#ifndef IDR_TRANSFORMS_SPECIALIZESTATE_H
#define IDR_TRANSFORMS_SPECIALIZESTATE_H

#include "idr/IR/Families/Terms.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/OwningOpRef.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/Hashing.h"
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

// A node's phases, each holding what it has, all between two waves:
// admitted and not built; built, detached, with its parameters' binding
// times; placed in the program as the function the schedule numbered,
// which is all a turn ever meets.
struct Requested {};
struct Built {
  FuncOp fn;
  llvm::SmallVector<BindingTime> times;
};
struct Placed {
  FunctionId id;
};
using Phase = std::variant<Requested, Built, Placed>;

// What the decisions of the component a copy joined made of its key's
// signature, between waves, each with the signature they gave it, at which
// every call made of it after is made: nothing, its signature its key's;
// its parameters lowered to what that component passes, its results its
// key's, each operand that claims more shared down to it at a call; or its
// results changed too (a result lowered to the hold its return then gives),
// which every call made of it then was converted to, and which a call made
// of it after gives its caller. Holds only descend, so each restatement
// claims no more than the one before, and results once changed stay
// changed.
struct AsKeyed {};
struct ParametersLowered {
  mlir::FunctionType type;
};
struct ResultsChanged {
  mlir::FunctionType type;
};
using Restated = std::variant<AsKeyed, ParametersLowered, ResultsChanged>;

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
  // What its body holds, which decides what a call in it may key a size by.
  // `own`: each closed index term its body holds where the code it came
  // from named an index variable, a set; a function the program held has
  // none, its own terms being its binders. `cycles`: the origins whose call
  // cycles the code it holds is from, a set. A copy holds its owner's body,
  // with the terms its signature key fixed put in, and a raise copy the
  // consumer of each function that asked for it too, whose calls are that
  // function's and stand in its cycles wherever the copy's origin is.
  llvm::SmallVector<families::Term> own{};
  llvm::SmallVector<FunctionId, 1> cycles{};
  // The parameters of its key's signature its copy no longer takes, by
  // position: those dropUnread erased when its component became final,
  // nothing reading them; none before. A call made of the copy after leaves
  // out the operands its key would pass there.
  llvm::BitVector unread{};
  // The functions a request of whose its key granted, each once: each
  // holds a call of the copy, which no caller's list holds, since a call
  // made by a request is no call of the program the schedule was read from
  // nor of a copy placed since.
  llvm::SmallVector<FunctionId, 1> askers{};
  // What the decisions of the component it joined made of its key's
  // signature, at its key's positions, before any parameter goes unread.
  Restated restated = AsKeyed{};

  // The signature its copy has, at its key's positions, before any
  // parameter goes unread: `keyed`, the one its key gives the copy, until
  // the decisions of the component it joined restate it.
  mlir::FunctionType signature(mlir::FunctionType keyed) const {
    return idr::match(
        restated, [&](AsKeyed) { return keyed; },
        [](const OneOf<ParametersLowered, ResultsChanged> auto &given) { return given.type; });
  }
};

// The consumer forms raising has met: each a detached function, interned
// by upstream's structural equivalence (idr-deduplicate's) within a bucket
// of this process's own hash, and known by the digest of its structure,
// which names the raise copies of it and is read once, when the form is
// first met. The number a form gets is the order workers met it in, so
// nothing outside this table reads it: a name reads the digest. Safe from
// any worker; a form is never written once interned.
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
  footprint::DenseMap<llvm::hash_code, llvm::SmallVector<FormId, 1>> byBucket;
  footprint::Vector<Form> forms;
};

// What a turn asked for at one call, kept by its requester until the wave
// settles, when it joins the table: the key, the name its copy takes (the
// key's digest, so the call names the copy before the copy exists), what
// the copy is to its origin's recursion, the origin, the function that
// asked and its node (none for a function the program held), and where it
// was asked.
struct Asked {
  Key key;
  mlir::FlatSymbolRefAttr name;
  std::optional<CopyKind> copy;
  FunctionId origin;
  FunctionId asker;
  const Node *parent;
  mlir::Location at;
};

// What a requester asked for: the keys it was given, by owner, against
// which every key of that owner it asks for later is judged, and what it
// has not taken yet. Held by the requester's turn, which one worker owns,
// so judging a request takes no lock.
class Requester {
public:
  llvm::ArrayRef<const PatternKey *> given(FunctionId owner) const;
  void give(const Asked &asked);
  // Whether anything was asked since the last take.
  bool asks() const { return !waiting.empty(); }
  // What was asked since the last take, in name order, each key once.
  llvm::SmallVector<Asked> take();

private:
  llvm::SmallVector<std::pair<FunctionId, llvm::SmallVector<const PatternKey *, 2>>, 4> keys;
  llvm::SmallVector<Asked> waiting;
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

// The table of one run: every node by key, the arena, the forms. A turn
// reads the table and asks; the pass thread, between waves, admits what
// was asked, builds each new copy and places it.
class Nodes {
public:
  explicit Nodes(const optimize::Schedule &schedule);
  ~Nodes();

  Arena &arena() { return keys; }
  Forms &forms() { return consumers; }

  // The node `fn` is, or null for a function the program held.
  const Node *find(FunctionId fn) const;

  // The copy `want`'s key names for `requester`, judged on its own state
  // and what the table holds, and asked of `state`: the table is not
  // written. None where the key grows one given before, a lift leaves no
  // structure, or a pattern or raise key names a copy whose results the
  // decisions of its component changed (ResultsChanged), which its caller,
  // reading its owner's results or its dispatch's, does not read: the call
  // stays a call, and nothing is asked. A signature key's want was judged
  // against the results its copy gives now (Node::signature), and its call
  // is made at them. A name another key's node holds is an internal error,
  // emitted at `at`.
  struct Grant {
    Asked asked;
    const PatternKey *key;
    llvm::SmallVector<Source> sources;
  };
  mlir::FailureOr<std::optional<Grant>> request(FunctionId requester, Requester &state,
                                                const Want &want, mlir::Operation *at);

  // The node of `key`, once the table admitted it, or null.
  const Node *known(const Key &key) const;

  // The signature the copy `key` names gives, as the table holds it: its
  // node's (Node::signature), or the key's where the table admitted none.
  // The one reading of a key's results, which a redirect judges its
  // caller by (signatureOf) while the turns run.
  mlir::FunctionType signatureOf(const SignatureKey *key) const;
  // Between waves, as `reader` is decided (openResults): the same reading,
  // `reader` kept among the key's readers, each once, which the next
  // restatement of the copy's results decides again (restate).
  mlir::FunctionType read(FunctionId reader, const SignatureKey *key);

  // Between waves: what the turns asked joins the table in name order, so
  // which turn asked first changes nothing, each key's node made the first
  // time, a function the program held under its name placed as it is; the
  // nodes made, to build, in that order. Two keys on one name are an
  // internal error.
  mlir::FailureOr<llvm::SmallVector<Node *>> admit(llvm::SmallVector<Asked> asked);
  // The node's function, built detached from its owner as it stands, no
  // turn running: it goes from requested to built. Each node is built by
  // one task, so builds run in parallel.
  mlir::LogicalResult build(Node &node);
  // The node, built, was numbered by the schedule as `id`.
  void place(Node &node, FunctionId id);
  // As `fn`'s component becomes final, between waves: where `fn` is a
  // node, its copy lost the parameters at `unread`, which its node keeps
  // for every call of it made after. Once per node: a component becomes
  // final once.
  void dropped(FunctionId fn, const llvm::BitVector &unread);
  // Between waves, as the schedule takes up the component of `fn`, a copy:
  // the decisions changed its signature from `before` to `after`, which its
  // node keeps (Restated) for every request of its key made after, whose
  // call is made at `after`. A hold only descends, so each restatement
  // claims no more than the one before. Where its results changed, the
  // functions that read them as they stood (read), each to be decided
  // again, which the key holds no more until each reads it again; none
  // where only its parameters were lowered, which no reader reads.
  llvm::SmallVector<FunctionId, 1> restate(FunctionId fn, mlir::FunctionType before,
                                           mlir::FunctionType after);
  // Once no turn runs: each placed copy's kind written on its function,
  // where the inline verdict reads it after the run.
  void writeCopies();

private:
  struct State;
  std::unique_ptr<State> state;
  Arena keys;
  Forms consumers;
};

// Where idr-redirect stands in a round of idr-optimize's inner pipeline:
// first, before leaf inlining and the e-graph see the member, deciding
// every call; or last, after the e-graph and constants, in a round that
// would otherwise be its member's last (it asked for no copy and inlined no
// leaf), deciding each call of a final callee that passes an operand at a
// hold its parameter does not take, which the round made after its first
// step decided: static data the e-graph placed at the argument, which the
// copy keyed to it counts nothing of. A copy that step asks for makes the
// round not the last, so the next one reads the call of the copy.
enum class InRound : std::uint8_t { First, Last };

// idr-redirect, a step of idr-optimize's inner pipeline: each call whose
// arguments compose a key, or whose result a dispatch consumes, requests
// its node and calls it, of the calls its place in the round decides.
std::unique_ptr<mlir::Pass> createRedirect(optimize::Schedule &schedule, Nodes &nodes,
                                           mlir::Pass::Statistic &redirected, InRound place);

struct Nodes::State {
  explicit State(const optimize::Schedule &schedule) : schedule(schedule) {}

  const optimize::Schedule &schedule;
  // What the table holds of one key: its node, null until admitted, and
  // the functions whose calls read the signature its copy gives (read)
  // since its results were last restated, each once.
  struct Entry {
    Node *node = nullptr;
    llvm::SmallVector<FunctionId, 1> readers{};
  };
  // Every node, in the order made, each where it was made for the run's
  // life, in the footprint's storage; and each key met, by its identity in
  // the arena.
  std::deque<Node, footprint::Allocator<Node>> nodes;
  footprint::DenseMap<const void *, Entry> byKey;
  // The node each placed function is, by its id, null for a function the
  // program held. It grows as copies are placed, each at the next id the
  // graph's editor minted, so an id past its end is a function no node is
  // yet. A name a node took is found through the graph's editor, the
  // program's one table of names: every node is placed before a turn runs.
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
