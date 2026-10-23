// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key, and their phases: each
// asked for by turns, which write nothing shared, and between waves, on
// the pass thread, made by the first ask of its key the wave admits, built
// and placed in the program by the schedule.
//
// A request is judged on its requester's own state (the keys it was given
// before, by owner) and on its request chain, the keys of the copies whose
// requests made it, read as a set: every node on a chain was placed before
// its requester ran, so the chain is whole when it is read, and the lift
// is over all of its peers at once, so neither the order requests met the
// table nor the order a chain lists its keys can reach a node.
//
// This ends. A key that grows an earlier one is refused, and one of an
// earlier one's shape that differs from it is lifted, which turns at least
// one scalar into a hole; so the keys one function is given are of
// pairwise distinct shapes, none growing one given before it, and the
// embedding being a well-quasi-order, they are finitely many. A raise key
// grows nothing and is never lifted: its forms are finitely many, each a
// consumer of code the program holds. A signature key is finitely many
// classes, holds, result layouts (a result as given, or marked open at one
// of finitely many grades, which a copy keyed open asks again of each tail
// callee and asks nothing more), kinds and grades, and sizes: a
// size keys a copy only from a call outside its callee's call cycle, or
// from one inside it whose terms for that axis are terms its caller's body
// holds as its own (Node's `own` and `cycles`, made here as each node joins
// the table), so every size a cycle's copies are keyed at entered it by one
// of the finitely many calls into it.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <cassert>

using namespace mlir;

namespace idr::specialize {

using namespace detail;

//===----------------------------------------------------------------------===//
// The requester's own state
//===----------------------------------------------------------------------===//

ArrayRef<const PatternKey *> Requester::given(FunctionId owner) const {
  for (const auto &[at, list] : keys)
    if (at == owner)
      return list;
  return {};
}

namespace {

// The key's identity in the arena.
const void *identityOf(const Key &key) {
  return idr::match(key, [](OneOf<const PatternKey *, const RaiseKey *, const SignatureKey *> auto k)
                             -> const void * { return k; });
}

} // namespace

// A pattern key is given, to be judged against later; every key asked
// waits to be taken, once.
void Requester::give(const Asked &asked) {
  idr::match(
      asked.key,
      [&](const PatternKey *key) {
        auto at = llvm::find_if(keys, [&](const auto &entry) { return entry.first == key->owner; });
        if (at == keys.end()) {
          keys.push_back({key->owner, {}});
          at = std::prev(keys.end());
        }
        if (!llvm::is_contained(at->second, key))
          at->second.push_back(key);
      },
      [](OneOf<const RaiseKey *, const SignatureKey *> auto) {});
  if (llvm::none_of(waiting, [&](const Asked &earlier) {
        return identityOf(earlier.key) == identityOf(asked.key);
      }))
    waiting.push_back(asked);
}

SmallVector<Asked> Requester::take() {
  SmallVector<Asked> out = std::move(waiting);
  waiting.clear();
  // Which order they were asked in changes nothing: the name fixes it.
  llvm::sort(out, [](const Asked &lhs, const Asked &rhs) {
    return lhs.name.getValue() < rhs.name.getValue();
  });
  return out;
}

//===----------------------------------------------------------------------===//
// The table
//===----------------------------------------------------------------------===//

Nodes::Nodes(const optimize::Schedule &schedule) : state(std::make_unique<State>(schedule)) {}

Nodes::~Nodes() = default;

// Read while the turns run, and written between waves alone.
const Node *Nodes::find(FunctionId fn) const { return state->placedAt(fn); }

const Node *Nodes::known(const Key &key) const {
  auto found = state->byKey.find(identityOf(key));
  return found == state->byKey.end() ? nullptr : found->second;
}

namespace {

FunctionId ownerOf(const Key &key) {
  return idr::match(
      key, [](const PatternKey *k) { return k->owner; },
      [](const RaiseKey *k) { return k->callee; }, [](const SignatureKey *k) { return k->owner; });
}

// The keys of `owner` on the request chain of `from`: its own, and those
// of each copy whose request made it, each read once. A set: its order is
// never read.
SmallVector<const PatternKey *> chainOf(const Node *from, FunctionId owner) {
  SmallVector<const PatternKey *> keys;
  SmallVector<const Node *> work;
  llvm::SmallPtrSet<const Node *, 8> seen;
  if (from)
    work.push_back(from);
  while (!work.empty()) {
    const Node *at = work.pop_back_val();
    if (!seen.insert(at).second)
      continue;
    idr::match(
        at->key,
        [&](const PatternKey *key) {
          if (key->owner == owner)
            keys.push_back(key);
        },
        [](OneOf<const RaiseKey *, const SignatureKey *> auto) {});
    llvm::append_range(work, at->parents);
  }
  return keys;
}

// The name a key gives its copy.
StringAttr nameFor(const Key &key, StringAttr owner, const Forms &forms) {
  return idr::match(
      key, [&](const PatternKey *k) { return nameOf<Patterns>(owner, k); },
      [&](const SignatureKey *k) { return nameOf<Signatures>(owner, k); },
      [&](const RaiseKey *k) {
        Bytes bytes;
        bytes.text(owner.getValue());
        bytes.digest128(forms.digestOf(k->form));
        llvm::XXH128_hash_t digest = bytes.digest();
        llvm::SmallString<96> name(owner.getValue());
        llvm::raw_svector_ostream os(name);
        os << ".raise." << llvm::format_hex_no_prefix(digest.high64, 16)
           << llvm::format_hex_no_prefix(digest.low64, 16);
        return StringAttr::get(owner.getContext(), name);
      });
}

// Each of `from` that `into` lacks: both are sets.
template <class T>
void addNew(SmallVectorImpl<T> &into, ArrayRef<T> from) {
  for (const T &each : from)
    if (!llvm::is_contained(into, each))
      into.push_back(each);
}

// What a node's copy holds of its owner, whose node is `owner` (none for a
// function the program held): the owner's body, with its terms and in its
// cycles, and its origin's cycle; and, of a signature key, each closed term
// it put where the owner named the binder it fixes.
void holdOwned(Node &node, const Node *owner) {
  node.cycles.push_back(node.origin);
  if (owner) {
    addNew<families::Term>(node.own, owner->own);
    addNew<FunctionId>(node.cycles, owner->cycles);
  }
  idr::match(
      node.key,
      [&](const SignatureKey *key) {
        SmallVector<families::Term> fixed;
        for (families::Term term :
             families::termsOf(key->indices.getTerms(), key->indices.getCount()))
          if (term.isClosed())
            fixed.push_back(term);
        addNew<families::Term>(node.own, fixed);
      },
      [](OneOf<const PatternKey *, const RaiseKey *> auto) {});
}

// A raise copy holds the consumer of a function that asked for it: that
// function's code, with the terms its body holds and in its cycles, read
// off its node `asker`; a function the program held, with none, holds no
// term and is its own cycle's origin, `origin`. Essential, two kinds: only
// a raise takes in code its owner did not hold.
void holdConsumer(Node &node, const Node *asker, FunctionId origin) {
  idr::match(
      node.key,
      [&](const RaiseKey *) {
        if (!asker) {
          addNew<FunctionId>(node.cycles, ArrayRef<FunctionId>(origin));
          return;
        }
        addNew<families::Term>(node.own, asker->own);
        addNew<FunctionId>(node.cycles, asker->cycles);
      },
      [](OneOf<const PatternKey *, const SignatureKey *> auto) {});
}

} // namespace

FailureOr<std::optional<Nodes::Grant>> Nodes::request(FunctionId requester, Requester &asking,
                                                      const Want &want, Operation *at) {
  State &s = *state;
  const optimize::Schedule &schedule = s.schedule;
  const Node *mine = find(requester);
  // What the judging keeps: the pattern key granted, and where each hole of
  // the call's key comes from.
  const PatternKey *granted = nullptr;
  SmallVector<Source> sources;

  // A pattern key is judged against what the requester was given of its
  // owner, and, where its copy is not yet in the program, against its
  // chain; lifted where earlier keys of its shape differ from it.
  auto judge = [&](const PatternWant &pattern) -> std::optional<const PatternKey *> {
    const PatternKey *key = pattern.key;
    for (unsigned hole = 0; hole < pattern.leaves.size(); ++hole)
      sources.push_back(Kept{hole});
    // A key the table holds is placed, its copy in the program, so its
    // chain is read no more.
    auto earlierOf = [&] {
      SmallVector<const PatternKey *> earlier(asking.given(key->owner));
      if (!known(Key(key)))
        llvm::append_range(earlier, chainOf(mine, key->owner));
      return earlier;
    };
    SmallVector<const PatternKey *> earlier = earlierOf();
    auto grown = [&] {
      return llvm::any_of(earlier, [&](const PatternKey *e) { return grows(*e, *key); });
    };
    if (grown())
      return std::nullopt;
    // The earlier keys of the key's shape, which it is lifted over.
    auto peersOf = [&] {
      SmallVector<const PatternKey *> peers;
      for (const PatternKey *e : earlier)
        if (e != key && sameShape(*e, *key))
          peers.push_back(e);
      return peers;
    };
    // Each lift turns at least one of the key's scalars into a hole, and a
    // key holds finitely many, so the lifts end.
    for (SmallVector<const PatternKey *> peers = peersOf(); !peers.empty(); peers = peersOf()) {
      SmallVector<Source> lifted;
      key = liftOver(keys, *key, peers, lifted);
      SmallVector<Source> composed;
      for (const Source &source : lifted)
        composed.push_back(idr::match(
            source, [&](Kept kept) { return sources[kept.hole]; },
            [](const Lifted &constant) { return Source(constant); }));
      sources = std::move(composed);
      if (llvm::none_of(key->params, [](const Pattern *p) { return p->hasStructure(); }))
        return std::nullopt;
      earlier = earlierOf();
      if (grown())
        return std::nullopt;
    }
    return key;
  };

  // A pattern key as judged (refused, as asked, or lifted); the others as
  // asked, since their keys are finitely many by how they are asked: a
  // raise's forms by the code the program holds, a signature's sizes by the
  // calls into each cycle, which the call's decision read.
  std::optional<Key> judged = idr::match(
      want,
      [&](const PatternWant &pattern) -> std::optional<Key> {
        std::optional<const PatternKey *> kept = judge(pattern);
        if (!kept)
          return std::nullopt;
        granted = *kept;
        return Key(*kept);
      },
      [](const RaiseWant &raise) -> std::optional<Key> { return Key(raise.key); },
      [](const SignatureWant &copy) -> std::optional<Key> { return Key(copy.key); });
  if (!judged)
    return std::optional<Grant>();
  Key key = *judged;

  FunctionId owner = ownerOf(key);
  StringAttr ownerName = schedule.symbolOf(owner);
  StringAttr name = nameFor(key, ownerName, consumers);
  // What the copy is to its origin's recursion, from the key and the
  // origin's component. A beta step that passes a closure something else
  // uses would copy that closure's code wherever it is inlined: a step,
  // which the verdict keeps.
  FunctionId origin = schedule.originOf(owner);
  auto copyOf = [&](const PatternKey *k) -> std::optional<CopyKind> {
    if (!schedule.onCycle(origin))
      return std::nullopt;
    return idr::match(
        fixes(*k, schedule.function(owner).getArgumentTypes()),
        [](FixesData) { return CopyKind::Step; },
        [&](const FixesClosures &closures) {
          bool outside = !closures.labels.empty() &&
                         llvm::none_of(closures.labels, [&](FlatSymbolRefAttr label) {
                           return schedule.sameComponent(schedule.graph.id(label), origin);
                         });
          return outside && !sharesClosure(cast<CallOp>(at)) ? CopyKind::Beta : CopyKind::Step;
        });
  };
  std::optional<CopyKind> copy = idr::match(
      key, [](const RaiseKey *) { return std::optional<CopyKind>(); },
      [](const SignatureKey *) { return std::optional<CopyKind>(); }, copyOf);

  // A name another key's node holds is the compiler's error. Every node is
  // placed while a turn runs, so the program's table of names finds it; the
  // asks of one wave meet each other's names when they are admitted.
  auto named = FlatSymbolRefAttr::get(name);
  if (std::optional<FunctionId> held = schedule.graph.find(named))
    if (const Node *holder = s.placedAt(*held);
        holder && identityOf(holder->key) != identityOf(key))
      return emitError(at->getLoc())
             << "internal error: idr-optimize: two keys name the copy @" << name.getValue();
  Asked asked{key, named, copy, origin, requester, mine, at->getLoc()};
  // Its own key, asked by a copy of its own recursion, is the copy's own
  // call already, and waits on nothing.
  if (!mine || identityOf(mine->key) != identityOf(key))
    asking.give(asked);
  return std::optional<Grant>(Grant{std::move(asked), granted, std::move(sources)});
}

FailureOr<SmallVector<Node *>> Nodes::admit(SmallVector<Asked> asked) {
  State &s = *state;
  llvm::stable_sort(asked, [](const Asked &lhs, const Asked &rhs) {
    return lhs.name.getValue() < rhs.name.getValue();
  });
  auto twoKeys = [](const Asked &each) -> LogicalResult {
    return emitError(each.at) << "internal error: idr-optimize: two keys name the copy @"
                              << each.name.getValue();
  };
  SmallVector<Node *> made;
  const Asked *previous = nullptr;
  for (const Asked &each : asked) {
    // The asks of one name stand together in name order, so another key
    // on a name asked in this wave is the one before it.
    if (previous && previous->name == each.name &&
        identityOf(previous->key) != identityOf(each.key))
      return twoKeys(each);
    previous = &each;
    Node *&slot = s.byKey[identityOf(each.key)];
    bool fresh = !slot;
    if (fresh) {
      // A name the program holds is a node placed by an earlier wave, which
      // another key took, or a function the program held when the run
      // began, the copy an earlier run made of this key.
      std::optional<FunctionId> earlier = s.schedule.graph.find(each.name);
      if (earlier && s.placedAt(*earlier))
        return twoKeys(each);
      Node &node =
          s.nodes.emplace_back(Node{each.key, each.copy, each.origin, each.name, {}, Requested{}});
      // Its owner is the callee its asker read, placed before any turn ran.
      holdOwned(node, s.placedAt(ownerOf(each.key)));
      if (earlier) {
        node.phase = Placed{*earlier};
        s.placeAt(*earlier, node);
      } else {
        made.push_back(&node);
      }
      slot = &node;
    }
    Node &node = *slot;
    // A step stays a step: a later request that shares makes no beta of it.
    if (each.copy == CopyKind::Step)
      node.copy = CopyKind::Step;
    bool waiting = idr::match(node.phase, [](const Placed &) { return false; },
                              [](const OneOf<Requested, Built> auto &) { return true; });
    if (waiting && each.parent && each.parent != &node &&
        !llvm::is_contained(node.parents, each.parent))
      node.parents.push_back(each.parent);
    // Every ask of a wave is admitted before its nodes are built and their
    // turns run, so a raise copy holds each consumer its wave asked with,
    // whatever order the asks came in.
    if (fresh || waiting)
      holdConsumer(node, each.parent, s.schedule.originOf(each.asker));
  }
  return made;
}

namespace {

// The binding times of a copy's parameters: for a pattern copy, its
// owner's at each of a parameter's holes; for a signature copy, its
// owner's; for a raise, its callee's, then varies for what the consumer
// reads.
SmallVector<BindingTime> inherited(const Key &key, FuncOp fn, ArrayRef<BindingTime> theirs) {
  return idr::match(
      key,
      [&](const PatternKey *k) {
        SmallVector<BindingTime> ours;
        for (auto [pattern, time] : llvm::zip_equal(k->params, theirs))
          ours.append(pattern->holes(), time);
        return ours;
      },
      [&](const SignatureKey *) { return SmallVector<BindingTime>(theirs); },
      [&](const RaiseKey *) {
        SmallVector<BindingTime> ours(theirs);
        ours.resize(fn.getNumArguments(), BindingTime::Varies);
        return ours;
      });
}

} // namespace

LogicalResult Nodes::build(Node &node) {
  State &s = *state;
  FunctionId owner = ownerOf(node.key);
  // No turn runs, so the owner reads as it stands, final or not.
  optimize::Readable from = s.schedule.readable(owner, owner);
  StringAttr name = node.name.getAttr();
  FailureOr<FuncOp> fn = idr::match(
      node.key, [&](const PatternKey *k) { return makeCopy<Patterns>(from.fn, k, name); },
      [&](const SignatureKey *k) { return makeCopy<Signatures>(from.fn, k, name); },
      [&](const RaiseKey *k) -> FailureOr<FuncOp> {
        return buildRaise(from.fn, *k, name, consumers);
      });
  if (failed(fn))
    return failure();
  node.phase = Built{*fn, inherited(node.key, *fn, from.times)};
  return success();
}

void Nodes::place(Node &node, FunctionId id) {
  node.phase = Placed{id};
  state->placeAt(id, node);
}

// A function the program held is no node: no key names it, so no call of
// it is made from a key, and its callers lost their operands with it.
void Nodes::dropped(FunctionId fn, const llvm::BitVector &unread) {
  Node *node = state->placedAt(fn);
  if (!node)
    return;
  assert(node->unread.empty() && "a copy's component becomes final once");
  node->unread = unread;
}

// Every copy's function says what it is, none included: a function the
// program held under a copy's name keeps nothing an earlier run wrote.
void Nodes::writeCopies() {
  for (const Node &node : state->nodes)
    idr::match(
        node.phase,
        [&](const Placed &placed) { state->schedule.function(placed.id).setCopy(node.copy); },
        [](const OneOf<Requested, Built> auto &) {});
}

} // namespace idr::specialize
