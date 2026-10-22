// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key, and their phases: each
// made by the first request of its key, claimed by one worker, built, and
// placed in the program by the schedule.
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
// consumer of code the program holds. A signature key's alphabet is
// finite.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Transforms/SpecializeState.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

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

// A pattern node's key is given, to be judged against later; its own key,
// asked by a copy of its own recursion, is given and never taken, since
// the call is already the copy's own.
void Requester::give(Node &node) {
  idr::match(
      node.key,
      [&](const PatternKey *key) {
        auto at = llvm::find_if(keys, [&](const auto &entry) { return entry.first == key->owner; });
        if (at == keys.end()) {
          keys.push_back({key->owner, {}});
          at = std::prev(keys.end());
        }
        if (!llvm::is_contained(at->second, key))
          at->second.push_back(key);
      },
      [](const auto *) {});
  if (!llvm::is_contained(waiting, &node))
    waiting.push_back(&node);
}

SmallVector<Node *> Requester::take() {
  SmallVector<Node *> out = std::move(waiting);
  waiting.clear();
  // Which order they were given in changes nothing: the name fixes it.
  llvm::sort(out, [](const Node *lhs, const Node *rhs) {
    return lhs->name.getValue() < rhs->name.getValue();
  });
  return out;
}

//===----------------------------------------------------------------------===//
// The table
//===----------------------------------------------------------------------===//

Nodes::Nodes(const optimize::Schedule &schedule) : state(std::make_unique<State>(schedule)) {}

Nodes::~Nodes() = default;

const Node *Nodes::find(FunctionId fn) const {
  std::lock_guard lock(state->mutex);
  return state->byFunction.lookup(fn);
}

namespace {

// The key's identity in the arena.
const void *identityOf(const Key &key) {
  return idr::match(key, [](const auto *k) -> const void * { return k; });
}

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
        [](const auto *) {});
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

} // namespace

FailureOr<std::optional<Nodes::Grant>> Nodes::request(FunctionId requester, Requester &asking,
                                                      const Want &want, Operation *at) {
  State &s = *state;
  const optimize::Schedule &schedule = s.schedule;
  const Node *mine = find(requester);
  Grant grant;

  // A pattern key is judged against what the requester was given of its
  // owner, and, where its copy is not yet in the program, against its
  // chain; lifted where earlier keys of its shape differ from it.
  auto judge = [&](const PatternWant &pattern) -> std::optional<const PatternKey *> {
    const PatternKey *key = pattern.key;
    for (unsigned hole = 0; hole < pattern.leaves.size(); ++hole)
      grant.sources.push_back(Kept{hole});
    auto earlierOf = [&] {
      SmallVector<const PatternKey *> earlier(asking.given(key->owner));
      bool known = false;
      {
        std::lock_guard lock(s.mutex);
        auto found = s.byKey.find(key);
        known = found != s.byKey.end() &&
                idr::match(found->second->phase, [](const Placed &) { return true; },
                           [](const auto &) { return false; });
      }
      if (!known)
        llvm::append_range(earlier, chainOf(mine, key->owner));
      return earlier;
    };
    SmallVector<const PatternKey *> earlier = earlierOf();
    auto grown = [&] {
      return llvm::any_of(earlier, [&](const PatternKey *e) { return grows(*e, *key); });
    };
    if (grown())
      return std::nullopt;
    while (true) {
      SmallVector<const PatternKey *> peers;
      for (const PatternKey *e : earlier)
        if (e != key && sameShape(*e, *key))
          peers.push_back(e);
      if (peers.empty())
        break;
      SmallVector<Source> lifted;
      key = liftOver(keys, *key, peers, lifted);
      SmallVector<Source> composed;
      for (const Source &source : lifted)
        composed.push_back(idr::match(
            source, [&](Kept kept) { return grant.sources[kept.hole]; },
            [](const Lifted &constant) { return Source(constant); }));
      grant.sources = std::move(composed);
      if (llvm::none_of(key->params, [](const Pattern *p) { return p->hasStructure(); }))
        return std::nullopt;
      earlier = earlierOf();
      if (grown())
        return std::nullopt;
    }
    return key;
  };

  // A pattern key as judged (refused, as asked, or lifted); the others as
  // asked, since their alphabets are finite.
  std::optional<Key> judged = idr::match(
      want,
      [&](const PatternWant &pattern) -> std::optional<Key> {
        std::optional<const PatternKey *> kept = judge(pattern);
        if (!kept)
          return std::nullopt;
        grant.key = *kept;
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

  std::lock_guard lock(s.mutex);
  Node *&slot = s.byKey[identityOf(key)];
  if (!slot) {
    if (s.byName.contains(name))
      return emitError(at->getLoc())
             << "internal error: idr-optimize: two keys name the copy @" << name.getValue();
    auto made = std::make_unique<Node>();
    made->key = key;
    made->copy = copy;
    made->origin = origin;
    made->name = FlatSymbolRefAttr::get(name);
    // A name the program held when the run began is the copy an earlier
    // run made of this key.
    if (std::optional<FunctionId> earlier = schedule.graph.find(FlatSymbolRefAttr::get(name))) {
      made->phase = Placed{*earlier};
      s.byFunction[*earlier] = made.get();
    }
    s.byName[name] = made.get();
    slot = made.get();
    s.nodes.push_back(std::move(made));
  }
  Node &node = *slot;
  // A step stays a step: a later request that shares makes no beta of it.
  if (copy == CopyKind::Step)
    node.copy = CopyKind::Step;
  bool waiting = idr::match(node.phase, [](const Placed &) { return false; },
                            [](const auto &) { return true; });
  if (waiting && mine && mine != &node && !llvm::is_contained(node.parents, mine))
    node.parents.push_back(mine);
  if (&node != mine)
    asking.give(node);
  grant.node = &node;
  return std::optional<Grant>(std::move(grant));
}

bool Nodes::claim(Node &node) {
  std::lock_guard lock(state->mutex);
  return idr::match(
      node.phase,
      [&](Requested) {
        node.phase = Claimed{};
        return true;
      },
      [](const auto &) { return false; });
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

LogicalResult Nodes::build(Node &node, FunctionId claimant) {
  State &s = *state;
  FunctionId owner = ownerOf(node.key);
  // The grant read the owner as the claimant may read it: final, or of the
  // claimant's own component, which only the claimant's turn writes.
  optimize::Readable from = s.schedule.readable(claimant, owner);
  StringAttr name = node.name.getAttr();
  FailureOr<FuncOp> fn = idr::match(
      node.key, [&](const PatternKey *k) { return makeCopy<Patterns>(from.fn, k, name); },
      [&](const SignatureKey *k) { return makeCopy<Signatures>(from.fn, k, name); },
      [&](const RaiseKey *k) -> FailureOr<FuncOp> {
        return buildRaise(from.fn, *k, name, consumers);
      });
  if (failed(fn))
    return failure();
  SmallVector<BindingTime> times = inherited(node.key, *fn, from.times);
  std::lock_guard lock(s.mutex);
  node.phase = Built{*fn, std::move(times)};
  return success();
}

void Nodes::place(Node &node, FunctionId id) {
  std::lock_guard lock(state->mutex);
  node.phase = Placed{id};
  state->byFunction[id] = &node;
}

bool Nodes::placed(const Node &node) const {
  std::lock_guard lock(state->mutex);
  return idr::match(node.phase, [](const Placed &) { return true; },
                    [](const auto &) { return false; });
}

// Every copy's function says what it is, none included: a function the
// program held under a copy's name keeps nothing an earlier run wrote.
void Nodes::writeCopies() {
  for (const std::unique_ptr<Node> &node : state->nodes)
    idr::match(
        node->phase,
        [&](const Placed &placed) { state->schedule.function(placed.id).setCopy(node->copy); },
        [](const auto &) {});
}

} // namespace idr::specialize
