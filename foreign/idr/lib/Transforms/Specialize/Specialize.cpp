// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key.
//
// A call's key is requested by the function that holds it, in its walk
// order; the first request of a key makes its node, named from the key's
// canonical hash, so every requester calls the same node, and calls it at
// once: the name is known before the node is built.
//
// A spec request is judged against the spec keys of its owner the function
// was given before, its own calls' and those of the code inlined into it
// alike, and, for a key whose node is not yet in the program, those of its
// owner on the function's request chain: its own key, and the chains of
// the nodes whose requests made it, back to functions the program held, so
// that a node's own recursion keeps one key. Keys compare only within one
// owner, so they are kept by owner. A key that grows an earlier one
// (Order: the earlier with more structure) is refused, and its call stays
// a call. A key of an earlier one's shape that differs from it is lifted
// (lift): each scalar where the two differ becomes a hole, a parameter of
// the node whose operand the call passes, and the lifted key is judged
// again; a lift that leaves no structure is refused. So `loop (Just n) =
// loop (Just (n - 1))`, from `Just 1000000`, is given loop[Just 1000000]
// and then loop[Just _], which every later call of it reaches; a float or a
// string that steps is lifted the same way.
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
// judged the same way, is finite. A raise request is not judged: a raise
// key grows nothing and is never lifted, and the raise keys are finitely
// many by their forms (Order).
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
#include "idr/Support/Worklist.h"
#include "idr/Transforms/Optimize.h"
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

// What one function has asked for: the spec key of every node it was
// given, by owner, which every spec key of that owner it asks for later is
// judged against, and the nodes the ready set has not taken yet, each once.
// A raise node it was given is taken and never judged against. Every
// request of the function goes through it.
class Requester {
public:
  ArrayRef<SpecKeyAttr> keysOf(StringAttr owner) { return given[owner]; }
  // `node`, whose key the request was granted, given to the function; its
  // own key, asked by a node of its own recursion, is given but not taken.
  void give(Node &node, bool self) {
    if (const auto *spec = std::get_if<SpecKeyAttr>(&node.key)) {
      SmallVector<SpecKeyAttr> &keys = given[spec->getOrigin()];
      if (!llvm::is_contained(keys, *spec))
        keys.push_back(*spec);
    }
    if (!self)
      waiting.push(&node);
  }
  // The next node given and not taken.
  std::optional<Node *> take() { return waiting.pop(); }

private:
  llvm::DenseMap<StringAttr, SmallVector<SpecKeyAttr>> given;
  OnceWorklist<Node *> waiting;
};

struct Nodes::State {
  explicit State(const Schedule &schedule) : schedule(schedule) {}

  std::mutex mutex;
  const Schedule &schedule;
  llvm::MapVector<Attribute, std::unique_ptr<Node>> byKey;
  llvm::DenseMap<StringAttr, Node *> byName;
  // What each function has asked for, by the function.
  llvm::DenseMap<Operation *, Requester> requesters;
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

// The spec keys of `owner` on the request chain of `from`: its own, and
// those on the chain of each node whose request made it. Each node of the
// chain is read once.
SmallVector<SpecKeyAttr> chainOf(const Node *from, StringAttr owner) {
  SmallVector<SpecKeyAttr> keys;
  OnceWorklist<const Node *> chain;
  if (from)
    chain.push(from);
  while (std::optional<const Node *> at = chain.pop()) {
    if (const auto *spec = std::get_if<SpecKeyAttr>(&(*at)->key);
        spec && spec->getOrigin() == owner)
      keys.push_back(*spec);
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

// Whether the node of `key` is in the program: a call of it makes nothing,
// so no chain judges it. Under the lock.
bool placed(const Nodes::State &s, Attribute key) {
  auto found = s.byKey.find(key);
  return found != s.byKey.end() && std::holds_alternative<Placed>(found->second->state);
}

// The kind a node's name says, by its key.
StringRef kindOf(const Key &key) {
  return std::visit(llvm::makeVisitor([](SpecKeyAttr) { return StringRef("spec"); },
                                      [](RaiseKey) { return StringRef("raise"); }),
                    key);
}

// The node of `key`, made if new, given to `requester`, which is `mine`
// when it is a node. A node not in the program yet takes the requester as
// a parent. A name another key holds is an internal error at `at`. A name
// is its key's content, so a function the program held under it when the
// run began is the node of the same key an earlier run made, already
// placed: the request calls it. Under the lock.
FailureOr<Node *> grant(Nodes::State &s, idr::FuncOp requester, const Node *mine, const Key &key,
                        Operation *at) {
  Attribute attr = attributeOf(key);
  auto found = s.byKey.find(attr);
  if (found == s.byKey.end()) {
    StringAttr owner = ownerOf(key);
    FailureOr<StringAttr> name =
        s.names.intern(at->getLoc(), owner.getValue(), kindOf(key), canonicalHash(attr));
    if (failed(name))
      return failure();
    auto made = std::make_unique<Node>();
    made->key = key;
    made->origin = originOf(s, owner);
    made->name = FlatSymbolRefAttr::get(*name);
    if (optimize::Node *earlier = s.schedule.held(*name))
      made->state = Placed{earlier};
    s.byName[*name] = made.get();
    found = s.byKey.insert({attr, std::move(made)}).first;
  }
  Node &node = *found->second;
  if (!std::holds_alternative<Placed>(node.state) && mine &&
      !llvm::is_contained(node.parents, mine))
    node.parents.push_back(mine);
  s.requesters[requester.getOperation()].give(node, &node == mine);
  return &node;
}

// What a spec request is granted: the node it calls, its key (the one asked
// for, or lifted against an earlier one of its shape), and for each hole of
// that key where the call's operand comes from.
struct SpecGrant {
  FlatSymbolRefAttr name;
  SpecKeyAttr key;
  SmallVector<Source> sources;
};

// The node `requester` is granted for `want`'s key, made if new; none when
// the key, as asked or lifted, grows an earlier key of its owner, or a lift
// leaves no structure, which makes nothing.
FailureOr<std::optional<SpecGrant>> requestSpec(Nodes::State &s, idr::FuncOp requester,
                                                const SpecWant &want, Operation *at) {
  std::lock_guard lock(s.mutex);
  Requester &asking = s.requesters[requester.getOperation()];
  const Node *mine = s.byName.lookup(requester.getSymNameAttr());
  SpecKeyAttr key = want.key;
  StringAttr owner = key.getOrigin();
  SmallVector<Source> sources;
  for (unsigned hole = 0; hole < want.leaves.size(); ++hole)
    sources.push_back(Kept{hole});
  // The keys the request is compared with: the owner's earlier ones, and
  // its chain's when the key is new.
  auto earlierOf = [&] {
    SmallVector<SpecKeyAttr> earlier(asking.keysOf(owner));
    if (!placed(s, key))
      llvm::append_range(earlier, chainOf(mine, owner));
    return earlier;
  };
  SmallVector<SpecKeyAttr> earlier = earlierOf();
  auto grows = [&] {
    return llvm::any_of(earlier, [&](SpecKeyAttr e) { return s.order.grows(e, key); });
  };
  auto differing = [&]() -> std::optional<SpecKeyAttr> {
    auto differs =
        llvm::find_if(earlier, [&](SpecKeyAttr e) { return e != key && sameShape(e, key); });
    if (differs == earlier.end())
      return std::nullopt;
    return *differs;
  };
  if (grows())
    return std::optional<SpecGrant>();
  // Each lift turns a scalar of the key into a hole, so the lifts end.
  for (std::optional<SpecKeyAttr> differs = differing(); differs; differs = differing()) {
    SmallVector<Source> lifted;
    key = lift(*differs, key, lifted);
    sources = llvm::map_to_vector(lifted, [&](const Source &source) {
      return std::visit(llvm::makeVisitor([&](Kept kept) { return sources[kept.hole]; },
                                          [](const Lifted &l) { return Source(l); }),
                        source);
    });
    if (llvm::none_of(key.getPatterns(), hasStructure))
      return std::optional<SpecGrant>();
    earlier = earlierOf();
    if (grows())
      return std::optional<SpecGrant>();
  }
  FailureOr<Node *> node = grant(s, requester, mine, key, at);
  if (failed(node))
    return failure();
  return std::optional<SpecGrant>(SpecGrant{(*node)->name, key, std::move(sources)});
}

// The node `requester` is granted for `want`'s key, made if new.
FailureOr<FlatSymbolRefAttr> requestRaise(Nodes::State &s, idr::FuncOp requester,
                                          const RaiseWant &want, Operation *at) {
  std::lock_guard lock(s.mutex);
  FailureOr<Node *> node =
      grant(s, requester, s.byName.lookup(requester.getSymNameAttr()), want.key, at);
  if (failed(node))
    return failure();
  return (*node)->name;
}

// The binding times of `callee`'s parameters as a call in `requester` sees
// them: within the recursion of the component both stand for, the callee's
// own; entering that component from outside, the callee is on no cycle the
// call is on, and each is fixed.
SmallVector<BindingTime> seenBy(Nodes::State &s, idr::FuncOp requester, StringAttr name,
                                const FinalCallee &callee) {
  StringAttr from, to;
  {
    std::lock_guard lock(s.mutex);
    from = originOf(s, requester.getSymNameAttr());
    to = originOf(s, name);
  }
  if (s.schedule.sameComponent(from, to))
    return SmallVector<BindingTime>(callee.times);
  idr::FuncOp fn = callee.fn;
  return SmallVector<BindingTime>(fn.getNumArguments(), BindingTime::Fixed);
}

// The binding times of a node's parameters: for a specialization, its
// owner's parameter's at each of the parameter's holes; for a raise, its
// callee's, then varies for what the consumer reads.
SmallVector<BindingTime> inherited(const Key &key, idr::FuncOp fn, ArrayRef<BindingTime> theirs) {
  return std::visit(llvm::makeVisitor(
                        [&](SpecKeyAttr spec) {
                          SmallVector<BindingTime> ours;
                          for (auto [pattern, time] : llvm::zip_equal(spec.getPatterns(), theirs))
                            ours.append(countHoles(pattern), time);
                          return ours;
                        },
                        [&](RaiseKey) {
                          SmallVector<BindingTime> ours(theirs);
                          ours.resize(fn.getNumArguments(), BindingTime::Varies);
                          return ours;
                        }),
                    key);
}

} // namespace

Nodes::Nodes(const Schedule &schedule) : state(std::make_unique<State>(schedule)) {}

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
  if (!std::holds_alternative<Requested>(node.state))
    return false;
  node.state = Claimed{};
  return true;
}

LogicalResult Nodes::build(Node &node) const {
  State &s = *state;
  // A node's key and name are fixed when it is made; only its state moves.
  StringAttr owner = ownerOf(node.key);
  std::optional<FinalCallee> from = s.schedule.finalCallee(owner);
  if (!from)
    return emitError(UnknownLoc::get(node.name.getContext()))
           << "internal error: the owner @" << owner.getValue() << " of "
           << node.name.getValue() << " is no final function of the program";
  StringAttr name = node.name.getAttr();
  FailureOr<idr::FuncOp> fn = std::visit(
      llvm::makeVisitor([&](SpecKeyAttr spec) { return buildSpec(from->fn, spec, name); },
                        [&](RaiseKey raise) -> FailureOr<idr::FuncOp> {
                          return buildRaise(from->fn, raise, name, s.forms);
                        }),
      node.key);
  if (failed(fn))
    return failure();
  SmallVector<BindingTime> times = inherited(node.key, *fn, from->times);
  std::lock_guard lock(s.mutex);
  node.state = Built{*fn, std::move(times)};
  return success();
}

void Nodes::insert(Node &node, idr::ProgramOp program, optimize::Node &made) const {
  // Its build found the owner final, and nothing erases a function while
  // idr-optimize runs.
  std::optional<FinalCallee> owner = state->schedule.finalCallee(ownerOf(node.key));
  assert(owner && "a built node's owner is a final function of the program");
  idr::FuncOp fn = std::get<Built>(node.state).fn;
  Block &body = *program.getBody();
  Block::iterator at = std::next(Block::iterator(owner->fn.getOperation()));
  for (; at != body.end(); ++at) {
    auto next = dyn_cast<idr::FuncOp>(*at);
    if (!next || !find(next.getSymNameAttr()) ||
        next.getSymName().compare(node.name.getValue()) >= 0)
      break;
  }
  body.getOperations().insert(at, fn.getOperation());
  std::lock_guard lock(state->mutex);
  node.state = Placed{&made};
}

bool Nodes::ready(const Node &node) const {
  std::lock_guard lock(state->mutex);
  const auto *in = std::get_if<Placed>(&node.state);
  return in && in->node->isFinal();
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
    // A callee not final is of the function's own component, or one it
    // waits on: nothing is read of it.
    std::optional<FinalCallee> callee = s.schedule.finalCallee(name);
    if (!callee)
      continue;
    FailureOr<std::optional<Want>> want =
        decide(call, requester, callee->fn, find(name), seenBy(s, fn, name, *callee), s.forms);
    if (failed(want))
      return failure();
    if (!*want)
      continue;
    // The kind decides what is asked, what the call becomes and the action
    // that names it.
    LogicalResult done = std::visit(
        llvm::makeVisitor(
            [&](const SpecWant &spec) -> LogicalResult {
              FailureOr<std::optional<SpecGrant>> granted = requestSpec(s, fn, spec, call);
              if (failed(granted))
                return failure();
              // Refused: the call stays a call.
              if (!*granted)
                return success();
              redirected += support::perform<SpecializeCloneAction>(call, [&] {
                SmallVector<Value> operands = operandsOf(
                    rewriter, call, spec, (*granted)->key, (*granted)->sources, s.schedule);
                redirect(rewriter, call, (*granted)->name, operands);
              });
              return success();
            },
            [&](const RaiseWant &raise) -> LogicalResult {
              FailureOr<FlatSymbolRefAttr> node = requestRaise(s, fn, raise, call);
              if (failed(node))
                return failure();
              redirected += support::perform<RaiseAction>(
                  call, [&] { redirect(rewriter, call, *node, raise); });
              return success();
            }),
        **want);
    if (failed(done))
      return failure();
  }
  return redirected;
}

} // namespace idr::specialize
