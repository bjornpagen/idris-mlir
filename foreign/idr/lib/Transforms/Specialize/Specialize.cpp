// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key.
//
// A call's key is requested by the function that holds it, in its walk
// order; the first request of a key makes its node, named from the key's
// canonical hash, so every requester calls the same node, and calls it at
// once: the name is known before the node is built.
//
// A key is made only when it grows no key on its requester's request
// chain: the requester's own key, and the chains of the nodes whose
// requests made the requester, back to functions the program held (Order).
// That ends specialization. Every chain is finite, since its keys are
// distinct and the order is a well-quasi-order; every function makes
// finitely many requests, at the calls its body holds as its pipeline
// leaves it. So the nodes are finitely many, whatever the program.
//
// Which requests made a node must not depend on which worker came first:
// a node's parents are the requesters whose requests of its key were
// followed in the wave that made it, each checked against its own chain,
// all of them finished before the ready set places the node and the node
// requests anything itself. A request of a key whose node is already in
// the program makes nothing, and calls it.
//
// A node is built once, by the worker that claims it, from its key and its
// owner's final body alone, its binding times its owner's by its key. The
// ready set puts it into the program after its owner, among the nodes
// there by name; its own turns redirect its calls, the first of them a
// call of its owner with its own key into its own recursion.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <mutex>

using namespace mlir;

namespace idr::specialize {

using namespace detail;

// What one function has asked for: the nodes, in the order first asked,
// and how many of them the ready set has taken.
struct Requester {
  llvm::SetVector<Node *> asked;
  size_t taken = 0;
};

struct Nodes::State {
  std::mutex mutex;
  const Schedule *schedule = nullptr;
  const BindingTimes *times = nullptr;
  const Holds *holds = nullptr;
  llvm::MapVector<Attribute, std::unique_ptr<Node>> byKey;
  llvm::DenseMap<StringAttr, Node *> byName;
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

// Whether `key` grows a key on the request chain of `from`: its own, or one
// on the chain of a node whose request made it.
bool growsOnChain(Order &order, const Node *from, Attribute key) {
  SmallVector<const Node *> work{from};
  llvm::DenseSet<const Node *> visited{from};
  while (!work.empty()) {
    const Node *at = work.pop_back_val();
    if (order.grows(at->key, key))
      return true;
    for (const Node *parent : at->parents)
      if (visited.insert(parent).second)
        work.push_back(parent);
  }
  return false;
}

// The node of `want`'s key for `requester`: made if new, and null when the
// key grows one on the requester's chain. A name that another key or a
// function of the program already holds is an internal error at `at`.
FailureOr<Node *> request(Nodes::State &s, idr::FuncOp requester, const Want &want,
                          Operation *at) {
  std::lock_guard lock(s.mutex);
  auto found = s.byKey.find(want.key);
  Node *node = found != s.byKey.end() ? found->second.get() : nullptr;
  if (!node || !s.schedule->lookup(node->name.getAttr())) {
    const Node *mine = s.byName.lookup(requester.getSymNameAttr());
    if (mine && growsOnChain(s.order, mine, want.key))
      return static_cast<Node *>(nullptr);
    if (!node) {
      StringRef kind = isa<SpecKeyAttr>(want.key) ? "spec" : "raise";
      FailureOr<StringAttr> name =
          s.names.intern(at->getLoc(), want.owner.getValue(), kind, canonicalHash(want.key));
      if (failed(name))
        return failure();
      if (s.schedule->lookup(*name))
        return at->emitError() << "internal error: two keys name " << name->getValue()
                               << ": a function of the program and " << canonicalText(want.key);
      auto made = std::make_unique<Node>();
      made->key = want.key;
      made->owner = want.owner;
      made->name = FlatSymbolRefAttr::get(*name);
      node = made.get();
      s.byName[*name] = node;
      s.byKey.insert({want.key, std::move(made)});
    }
    if (mine && !llvm::is_contained(node->parents, mine))
      node->parents.push_back(mine);
  }
  if (node->fn != requester)
    s.requesters[requester.getOperation()].asked.insert(node);
  return node;
}

// The function the program held that `fn` stands for: itself, or for a
// node what it was cloned from, back to a function the program held.
StringAttr originOf(const Nodes::State &s, StringAttr fn) {
  while (const Node *node = s.byName.lookup(fn))
    fn = node->owner;
  return fn;
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
  if (s.schedule->sameComponent(from, to))
    return s.times->of(callee.getSymNameAttr());
  return SmallVector<BindingTime>(callee.getNumArguments(), BindingTime::Free);
}

// The binding times of a node's parameters: for a specialization, its
// owner's parameter's at each of the parameter's holes; for a raise, its
// callee's, then other for what the consumer reads.
SmallVector<BindingTime> inherited(const Node &node, idr::FuncOp fn,
                                   ArrayRef<BindingTime> theirs) {
  SmallVector<BindingTime> ours;
  if (auto spec = dyn_cast<SpecKeyAttr>(node.key)) {
    for (auto [p, pattern] : llvm::enumerate(spec.getPatterns()))
      ours.append(countHoles(pattern), p < theirs.size() ? theirs[p] : BindingTime::Other);
    return ours;
  }
  llvm::append_range(ours, theirs);
  ours.resize(fn.getNumArguments(), BindingTime::Other);
  return ours;
}

} // namespace

Nodes::Nodes(Operation *, AnalysisManager &) : state(std::make_unique<State>()) {}

Nodes::~Nodes() = default;

bool Nodes::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Nodes>();
}

void Nodes::start(const Schedule &schedule, const BindingTimes &times, const Holds &holds) const {
  std::lock_guard lock(state->mutex);
  state->schedule = &schedule;
  state->times = &times;
  state->holds = &holds;
}

const Node *Nodes::find(StringAttr fn) const {
  std::lock_guard lock(state->mutex);
  return state->byName.lookup(fn);
}

SmallVector<Node *> Nodes::takeRequests(idr::FuncOp requester) const {
  std::lock_guard lock(state->mutex);
  auto it = state->requesters.find(requester.getOperation());
  if (it == state->requesters.end())
    return {};
  Requester &r = it->second;
  ArrayRef<Node *> asked = r.asked.getArrayRef();
  SmallVector<Node *> out(asked.drop_front(r.taken));
  r.taken = asked.size();
  return out;
}

bool Nodes::claim(Node &node) const {
  std::lock_guard lock(state->mutex);
  return state->claimed.insert(&node).second;
}

LogicalResult Nodes::build(Node &node) const {
  State &s = *state;
  idr::FuncOp owner = s.schedule->lookup(node.owner);
  if (!owner)
    return emitError(UnknownLoc::get(node.key.getContext()))
           << "internal error: the owner @" << node.owner.getValue() << " of "
           << node.name.getValue() << " is no function of the program";
  FailureOr<idr::FuncOp> fn = failure();
  if (auto spec = dyn_cast<SpecKeyAttr>(node.key))
    fn = buildSpec(owner, spec, node.name.getAttr());
  else if (auto raise = dyn_cast<KeyRaiseAttr>(node.key))
    fn = buildRaise(owner, raise, node.name.getAttr());
  else
    return owner.emitError() << "internal error: " << canonicalText(node.key)
                              << " is no specialization key";
  if (failed(fn))
    return failure();
  SmallVector<BindingTime> times = inherited(node, *fn, s.times->of(node.owner));
  std::lock_guard lock(s.mutex);
  node.times = std::move(times);
  node.fn = *fn;
  return success();
}

void Nodes::insert(Node &node, idr::ProgramOp program) const {
  idr::FuncOp owner = state->schedule->lookup(node.owner);
  Block &body = *program.getBody();
  Block::iterator at = owner ? std::next(Block::iterator(owner.getOperation())) : body.end();
  for (; at != body.end(); ++at) {
    auto fn = dyn_cast<idr::FuncOp>(*at);
    if (!fn || !find(fn.getSymNameAttr()) || fn.getSymName().compare(node.name.getValue()) >= 0)
      break;
  }
  body.getOperations().insert(at, node.fn.getOperation());
}

LogicalResult Nodes::redirectCalls(idr::FuncOp fn, unsigned &redirected, bool &changed) const {
  State &s = *state;
  const Node *requester = find(fn.getSymNameAttr());
  SmallVector<idr::CallOp> calls;
  fn.walk<WalkOrder::PreOrder>([&](idr::CallOp call) { calls.push_back(call); });
  Erased erased;
  IRRewriter rewriter(fn.getContext(), &erased);
  for (idr::CallOp call : calls) {
    if (erased.ops.contains(call.getOperation()))
      continue;
    StringAttr name = call.getCalleeAttr().getAttr();
    idr::FuncOp callee = s.schedule->lookup(name);
    if (!callee || !s.schedule->isFinal(callee))
      continue;
    std::optional<Want> want = decide(call, requester, callee, find(name),
                                      seenBy(s, fn, callee), *s.holds, s.forms);
    if (!want)
      continue;
    FailureOr<Node *> node = request(s, fn, *want, call);
    if (failed(node))
      return failure();
    if (!*node)
      continue;
    FlatSymbolRefAttr target = (*node)->name;
    auto transform = [&] { redirect(rewriter, call, target, *want); };
    bool done = want->consumer ? support::perform<RaiseAction>(call, transform)
                               : support::perform<SpecializeCloneAction>(call, transform);
    if (done) {
      ++redirected;
      changed = true;
    }
  }
  return success();
}

} // namespace idr::specialize
