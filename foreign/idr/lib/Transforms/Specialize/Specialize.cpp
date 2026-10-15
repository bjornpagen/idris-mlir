// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key.
//
// A call's key is requested by the function that holds it, in its walk
// order; the first request of a key makes its node, named from the key's
// canonical hash, so every requester calls the same node, and calls it at
// once: the name is known before the node is built.
//
// A request is judged against the keys its function was given before, its
// own calls' and those of the code inlined into it alike, and, for a key
// not yet in the program, those on the function's request chain: its own
// key, and the chains of the nodes whose requests made it, back to
// functions the program held, so that a node's own recursion keeps one
// key. A key that grows an earlier one (Order: the earlier with more
// structure) is refused, and its call stays a call. A key of an earlier
// one's shape that differs from it is lifted (lift): each scalar where the
// two differ becomes a hole, a parameter of the node whose operand the
// call passes, and the lifted key is judged again; a lift that leaves no
// structure is refused. So `loop (Just n) = loop (Just (n - 1))`, from
// `Just 1000000`, is given loop[Just 1000000] and then loop[Just _], which
// every later call of it reaches; a float or a string that steps is
// lifted the same way.
//
// This ends. Two keys of one shape that differ differ in a scalar, so each
// lift turns at least one scalar of the key into a hole, and a request
// lifts finitely often. The keys one function is given are then of
// pairwise distinct shapes, and none grows one given before it. What a
// key embeds in is a function of its shape, the shapes of one owner that
// embed both ways in one another are finitely many (finitely many tags,
// kinds and holes fill a shape of one size), and the embedding is a
// well-quasi-order (Kruskal's theorem, Dickson's lemma for its flat case).
// So an infinite sequence of distinct shapes would hold an earlier one
// embedded in a later one that does not embed back, which the table
// refuses: a function is given finitely many nodes, and a request chain,
// judged the same way, is finite. A raise key grows nothing and is never
// lifted, and the raise keys are finitely many by their forms (Order).
//
// Which requests made a node must not depend on which worker came first:
// a node's parents are the requesters whose requests of its key were
// followed in the wave that made it, each checked against its own chain,
// all of them finished before the ready set places the node and the node
// requests anything itself. A request of a key whose node is already in
// the program, judged against the requester's own keys alone, makes
// nothing, and calls it.
//
// A node is built once, by the worker that claims it, from its key and its
// owner's final body alone, its binding times its owner's by its key. The
// ready set puts it into the program after its owner, among the nodes
// there by name; its own turns redirect its calls, the first of them a
// call of its owner with its own key into its own recursion.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Support/Worklist.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <mutex>
#include <optional>

using namespace mlir;

namespace idr::specialize {

using namespace detail;

// What one function has asked for: the key of every node it was given,
// which every key it asks for later is judged against, and the nodes the
// ready set has not taken yet, each once. Every request of the function
// goes through it.
class Requester {
public:
  ArrayRef<Key> keys() const { return given; }
  // `node`, whose key the request was granted, given to the function; its
  // own key, asked by a node of its own recursion, is given but not taken.
  void give(Node &node, bool self) {
    if (!llvm::is_contained(given, node.key))
      given.push_back(node.key);
    if (!self)
      waiting.push(&node);
  }
  // The next node given and not taken.
  std::optional<Node *> take() { return waiting.pop(); }

private:
  SmallVector<Key> given;
  OnceWorklist<Node *> waiting;
};

struct Nodes::State {
  State(const Schedule &schedule, const BindingTimes &times, const CalleeEffects &effects)
      : schedule(schedule), times(times), effects(effects) {}

  std::mutex mutex;
  const Schedule &schedule;
  const BindingTimes &times;
  const CalleeEffects &effects;
  llvm::MapVector<Attribute, std::unique_ptr<Node>> byKey;
  llvm::DenseMap<StringAttr, Node *> byName;
  // What each function has asked for, by the function.
  llvm::DenseMap<Operation *, Requester> requesters;
  llvm::DenseSet<Node *> claimed;
  ContentNames names;
  Order order;
  Forms forms;
};

namespace {

// The ops a redirect erased, so the walk skips them.
struct Erased : RewriterBase::Listener {
  void notifyOperationErased(Operation *op) override { ops.insert(op); }
  llvm::DenseSet<Operation *> ops;
};

// The keys on the request chain of `from`: its own, and those on the chain
// of each node whose request made it. Each node of the chain is read once.
SmallVector<Key> chainOf(const Node *from) {
  SmallVector<Key> keys;
  OnceWorklist<const Node *> chain;
  if (from)
    chain.push(from);
  while (std::optional<const Node *> at = chain.pop()) {
    keys.push_back((*at)->key);
    for (const Node *parent : (*at)->parents)
      chain.push(parent);
  }
  return keys;
}

// The function the program held that `fn` stands for: itself, or for a
// node the origin it was made with.
StringAttr originOf(const Nodes::State &s, StringAttr fn) {
  const Node *node = s.byName.lookup(fn);
  return node ? node->origin : fn;
}

// Whether two keys are spec keys of one shape that differ.
bool differsInShape(const Key &earlier, const Key &key) {
  const auto *before = std::get_if<SpecKeyAttr>(&earlier);
  const auto *after = std::get_if<SpecKeyAttr>(&key);
  return before && after && *before != *after && sameShape(*before, *after);
}

// Whether a key specializes on anything: a raise does, a spec key when a
// pattern of it is more than a hole.
bool structured(const Key &key) {
  return std::visit(llvm::makeVisitor(
                        [](SpecKeyAttr spec) {
                          return !llvm::all_of(spec.getPatterns(), llvm::IsaPred<KeyHoleAttr>);
                        },
                        [](KeyRaiseAttr) { return true; }),
                    key);
}

// What a request is granted: the node it calls, its key, and for each hole
// of the key where the call's operand comes from.
struct Granted {
  FlatSymbolRefAttr name;
  Key key;
  SmallVector<Source> sources;
};

// The node `requester` is granted for `want`'s key, made if new: the key,
// or the key lifted against an earlier one of its shape; none when a key
// grows an earlier one or a lift leaves no structure, which makes nothing.
// A name that another key or a function of the program already holds is an
// internal error at `at`.
FailureOr<std::optional<Granted>> request(Nodes::State &s, idr::FuncOp requester,
                                          const Want &want, Operation *at) {
  std::lock_guard lock(s.mutex);
  Requester &asking = s.requesters[requester.getOperation()];
  const Node *mine = s.byName.lookup(requester.getSymNameAttr());
  SmallVector<Key> chain = chainOf(mine);
  Key key = want.key;
  SmallVector<Source> sources;
  for (unsigned hole = 0; hole < want.operands.size(); ++hole)
    sources.push_back(Kept{hole});
  // Whether the key's node is in the program: a call of it makes nothing,
  // so the chain does not judge it.
  auto inProgram = [&] {
    auto found = s.byKey.find(attributeOf(key));
    return found != s.byKey.end() && s.schedule.lookup(found->second->name.getAttr());
  };
  // The key judged against the earlier keys: refused when it grows one,
  // else the earlier key of its shape it differs from, if any.
  struct Refused {};
  using Verdict = std::variant<Refused, std::optional<SpecKeyAttr>>;
  auto judge = [&]() -> Verdict {
    SmallVector<const Key *> earlier =
        llvm::map_to_vector(asking.keys(), [](const Key &k) { return &k; });
    if (!inProgram())
      for (const Key &k : chain)
        earlier.push_back(&k);
    if (llvm::any_of(earlier, [&](const Key *e) { return s.order.grows(*e, key); }))
      return Refused{};
    for (const Key *e : earlier)
      if (differsInShape(*e, key))
        return std::optional<SpecKeyAttr>(std::get<SpecKeyAttr>(*e));
    return std::optional<SpecKeyAttr>();
  };
  // Each lift turns a scalar of the key into a hole, so the lifts end.
  Verdict verdict = judge();
  for (const auto *against = std::get_if<std::optional<SpecKeyAttr>>(&verdict);
       against && *against; against = std::get_if<std::optional<SpecKeyAttr>>(&verdict)) {
    SmallVector<Source> lifted;
    key = lift(**against, std::get<SpecKeyAttr>(key), lifted);
    sources = llvm::map_to_vector(lifted, [&](const Source &source) {
      return std::visit(llvm::makeVisitor([&](Kept kept) { return sources[kept.hole]; },
                                          [](const Lifted &l) { return Source(l); }),
                        source);
    });
    if (!structured(key))
      return std::optional<Granted>();
    verdict = judge();
  }
  if (std::holds_alternative<Refused>(verdict))
    return std::optional<Granted>();

  Attribute attr = attributeOf(key);
  auto found = s.byKey.find(attr);
  if (found == s.byKey.end() || !s.schedule.lookup(found->second->name.getAttr())) {
    if (found == s.byKey.end()) {
      StringRef kind = std::holds_alternative<SpecKeyAttr>(key) ? "spec" : "raise";
      FailureOr<StringAttr> name =
          s.names.intern(at->getLoc(), want.owner.getValue(), kind, canonicalHash(attr));
      if (failed(name))
        return failure();
      if (s.schedule.lookup(*name))
        return at->emitError() << "internal error: two keys name " << name->getValue()
                               << ": a function of the program and " << canonicalText(attr);
      auto made = std::make_unique<Node>();
      made->key = key;
      made->owner = want.owner;
      made->origin = originOf(s, want.owner);
      made->name = FlatSymbolRefAttr::get(*name);
      s.byName[*name] = made.get();
      found = s.byKey.insert({attr, std::move(made)}).first;
    }
    Node &node = *found->second;
    if (mine && !llvm::is_contained(node.parents, mine))
      node.parents.push_back(mine);
  }
  Node &node = *found->second;
  asking.give(node, node.fn == requester);
  return std::optional<Granted>(Granted{node.name, key, std::move(sources)});
}

// The binding times of `callee`'s parameters as a call in `requester` sees
// them: within the recursion of the component both stand for, the callee's
// own; entering that component from outside, the callee is on no cycle the
// call is on, and each is free.
SmallVector<BindingTime> seenBy(Nodes::State &s, idr::FuncOp requester, idr::FuncOp callee) {
  StringAttr from, to;
  {
    std::lock_guard lock(s.mutex);
    from = originOf(s, requester.getSymNameAttr());
    to = originOf(s, callee.getSymNameAttr());
  }
  if (s.schedule.sameComponent(from, to))
    return SmallVector<BindingTime>(s.times.of(callee.getSymNameAttr()));
  return SmallVector<BindingTime>(callee.getNumArguments(), BindingTime::Free);
}

// The binding times of a node's parameters: for a specialization, its
// owner's parameter's at each of the parameter's holes; for a raise, its
// callee's, then other for what the consumer reads.
SmallVector<BindingTime> inherited(const Node &node, idr::FuncOp fn,
                                   ArrayRef<BindingTime> theirs) {
  SmallVector<BindingTime> ours;
  if (const auto *spec = std::get_if<SpecKeyAttr>(&node.key)) {
    for (auto [p, pattern] : llvm::enumerate(spec->getPatterns()))
      ours.append(countHoles(pattern), p < theirs.size() ? theirs[p] : BindingTime::Other);
    return ours;
  }
  llvm::append_range(ours, theirs);
  ours.resize(fn.getNumArguments(), BindingTime::Other);
  return ours;
}

} // namespace

Nodes::Nodes(const Schedule &schedule, const BindingTimes &times, const CalleeEffects &effects)
    : state(std::make_unique<State>(schedule, times, effects)) {}

Nodes::~Nodes() = default;

const Node *Nodes::find(StringAttr fn) const {
  std::lock_guard lock(state->mutex);
  return state->byName.lookup(fn);
}

SmallVector<Node *> Nodes::takeRequests(idr::FuncOp requester) const {
  std::lock_guard lock(state->mutex);
  auto it = state->requesters.find(requester.getOperation());
  if (it == state->requesters.end())
    return {};
  SmallVector<Node *> out;
  while (std::optional<Node *> asked = it->second.take())
    out.push_back(*asked);
  // Which order the worklist hands them out in changes nothing: the name
  // fixes it.
  llvm::sort(out, [](const Node *lhs, const Node *rhs) {
    return lhs->name.getValue() < rhs->name.getValue();
  });
  return out;
}

bool Nodes::claim(Node &node) const {
  std::lock_guard lock(state->mutex);
  return state->claimed.insert(&node).second;
}

LogicalResult Nodes::build(Node &node) const {
  State &s = *state;
  idr::FuncOp owner = s.schedule.lookup(node.owner);
  if (!owner)
    return emitError(UnknownLoc::get(node.name.getContext()))
           << "internal error: the owner @" << node.owner.getValue() << " of "
           << node.name.getValue() << " is no function of the program";
  StringAttr name = node.name.getAttr();
  FailureOr<idr::FuncOp> fn = std::visit(
      llvm::makeVisitor([&](SpecKeyAttr spec) { return buildSpec(owner, spec, name); },
                        [&](KeyRaiseAttr raise) { return buildRaise(owner, raise, name); }),
      node.key);
  if (failed(fn))
    return failure();
  SmallVector<BindingTime> times = inherited(node, *fn, s.times.of(node.owner));
  std::lock_guard lock(s.mutex);
  node.times = std::move(times);
  node.fn = *fn;
  return success();
}

void Nodes::insert(Node &node, idr::ProgramOp program) const {
  // Its build found the owner, which nothing erases while idr-optimize runs.
  idr::FuncOp owner = state->schedule.lookup(node.owner);
  assert(owner && "a built node's owner is a function of the program");
  Block &body = *program.getBody();
  Block::iterator at = std::next(Block::iterator(owner.getOperation()));
  for (; at != body.end(); ++at) {
    auto fn = dyn_cast<idr::FuncOp>(*at);
    if (!fn || !find(fn.getSymNameAttr()) || fn.getSymName().compare(node.name.getValue()) >= 0)
      break;
  }
  body.getOperations().insert(at, node.fn.getOperation());
}

FailureOr<unsigned> Nodes::redirectCalls(idr::FuncOp fn) const {
  State &s = *state;
  const Node *requester = find(fn.getSymNameAttr());
  SmallVector<idr::CallOp> calls;
  fn.walk<WalkOrder::PreOrder>([&](idr::CallOp call) { calls.push_back(call); });
  Erased erased;
  IRRewriter rewriter(fn.getContext(), &erased);
  unsigned redirected = 0;
  for (idr::CallOp call : calls) {
    if (erased.ops.contains(call.getOperation()))
      continue;
    StringAttr name = call.getCalleeAttr().getAttr();
    idr::FuncOp callee = s.schedule.finalFunction(name);
    if (!callee)
      continue;
    std::optional<Want> want = decide(call, requester, callee, find(name),
                                      seenBy(s, fn, callee), s.effects, s.forms);
    if (!want)
      continue;
    FailureOr<std::optional<Granted>> granted = request(s, fn, *want, call);
    if (failed(granted))
      return failure();
    if (!*granted)
      continue;
    auto transform = [&] {
      Want called = *want;
      called.operands =
          operandsOf(rewriter, call, *want, (*granted)->key, (*granted)->sources, s.schedule);
      redirect(rewriter, call, (*granted)->name, called);
    };
    bool done = want->consumer ? support::perform<RaiseAction>(call, transform)
                               : support::perform<SpecializeCloneAction>(call, transform);
    redirected += done;
  }
  return redirected;
}

} // namespace idr::specialize
