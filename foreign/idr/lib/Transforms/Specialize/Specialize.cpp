// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key.
//
// A call's key is requested by the function that holds it, in its walk
// order; the first request of a key makes its node, named from the key, so
// every requester calls the same node, and calls it at once: the name is
// known before the node is built. A function requests at most
// kKeysPerOwner distinct keys of one owner, counted in its own call-site
// order, so which call stays a call of the owner is a function of the
// function's own body, the same on every schedule.
//
// A node is built once, by the worker that claims it, from its key and its
// owner's final body alone; its binding times are its owner's, by its key,
// written once, since its recursion goes where its owner's goes; then its
// own calls are redirected, so a call of its owner with its own key is
// already its own call when its component becomes ready. The ready set
// puts it into the module after its owner, among the nodes there by name.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/Support/raw_ostream.h"

#include <mutex>

using namespace mlir;

namespace idr::specialize {

using namespace detail;

// What one function has asked for: the nodes, in the order first asked,
// how many of them the ready set has taken, and the distinct keys it has
// asked of each owner.
struct Requester {
  llvm::SetVector<Node *> asked;
  size_t taken = 0;
  llvm::DenseMap<StringAttr, unsigned> perOwner;
  llvm::DenseSet<Attribute> keys;
};

struct Nodes::State {
  std::mutex mutex;
  const Schedule *schedule = nullptr;
  BindingTimes *times = nullptr;
  const Holds *holds = nullptr;
  llvm::MapVector<Attribute, std::unique_ptr<Node>> byKey;
  llvm::DenseMap<StringAttr, Node *> byName;
  llvm::DenseMap<Operation *, Requester> requesters;
  llvm::DenseSet<Node *> claimed;
};

namespace {

// What a key's text is: the key printed.
std::string textOf(Attribute key) {
  std::string text;
  llvm::raw_string_ostream os(text);
  key.print(os);
  return text;
}

// The ops a redirect erased, so the walk skips them.
struct Erased : RewriterBase::Listener {
  void notifyOperationErased(Operation *op) override { ops.insert(op); }
  llvm::DenseSet<Operation *> ops;
};

// The node of `want`'s key for `requester`: made if new; null when the
// requester has asked kKeysPerOwner other keys of the owner. A name that
// another key or a function of the module already holds is an internal
// error at `at`.
FailureOr<Node *> request(Nodes::State &s, idr::FuncOp requester, const Want &want,
                          Operation *at) {
  std::string error;
  Node *node = nullptr;
  {
    std::lock_guard lock(s.mutex);
    Requester &r = s.requesters[requester.getOperation()];
    if (!r.keys.contains(want.key)) {
      unsigned &count = r.perOwner[want.owner];
      if (count >= kKeysPerOwner)
        return static_cast<Node *>(nullptr);
      ++count;
      r.keys.insert(want.key);
    }
    if (auto it = s.byKey.find(want.key); it != s.byKey.end()) {
      node = it->second.get();
    } else {
      StringRef kind = isa<SpecKeyAttr>(want.key) ? "spec" : "raise";
      std::string text = textOf(want.key);
      auto name = StringAttr::get(want.key.getContext(),
                                  contentName(want.owner.getValue(), kind, text));
      if (Node *other = s.byName.lookup(name))
        error = "internal error: two keys name " + name.str() + ": " + textOf(other->key) +
                " and " + text;
      else if (s.schedule->lookup(name))
        error = "internal error: two keys name " + name.str() + ": a function of the module and " +
                text;
      else {
        auto made = std::make_unique<Node>(
            Node{want.key, want.owner, FlatSymbolRefAttr::get(name), idr::FuncOp()});
        node = made.get();
        s.byName[name] = node;
        s.byKey.insert({want.key, std::move(made)});
      }
    }
    if (node && node->fn != requester)
      r.asked.insert(node);
  }
  if (!error.empty())
    return at->emitError(error);
  return node;
}

// The binding times of a node's parameters: for a specialization, its
// owner's parameter's at each of the parameter's holes; for a raise, its
// callee's, then other for what the consumer reads.
SmallVector<BindingTime> inherited(const Node &node, ArrayRef<BindingTime> theirs) {
  SmallVector<BindingTime> ours;
  if (auto spec = dyn_cast<SpecKeyAttr>(node.key)) {
    for (auto [p, pattern] : llvm::enumerate(spec.getPatterns()))
      ours.append(countHoles(pattern), p < theirs.size() ? theirs[p] : BindingTime::Other);
    return ours;
  }
  llvm::append_range(ours, theirs);
  ours.resize(idr::FuncOp(node.fn).getNumArguments(), BindingTime::Other);
  return ours;
}

} // namespace

Nodes::Nodes(Operation *, AnalysisManager &) : state(std::make_unique<State>()) {}

Nodes::~Nodes() = default;

bool Nodes::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Nodes>();
}

void Nodes::start(const Schedule &schedule, BindingTimes &times, const Holds &holds) const {
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
           << node.name.getValue() << " is no function of the module";
  FailureOr<idr::FuncOp> fn = failure();
  if (auto spec = dyn_cast<SpecKeyAttr>(node.key))
    fn = buildSpec(owner, spec, node.name.getAttr());
  else if (auto raise = dyn_cast<KeyRaiseAttr>(node.key))
    fn = buildRaise(owner, raise, node.name.getAttr());
  else
    return owner.emitError() << "internal error: " << node.key << " is no specialization key";
  if (failed(fn))
    return failure();
  {
    std::lock_guard lock(s.mutex);
    node.fn = *fn;
  }
  s.times->inherit(node.name.getAttr(), inherited(node, s.times->of(node.owner)));
  unsigned redirected = 0;
  bool changed = false;
  return redirectCalls(*fn, redirected, changed);
}

void Nodes::insert(Node &node, ModuleOp module) const {
  idr::FuncOp owner = state->schedule->lookup(node.owner);
  Block &body = *module.getBody();
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
    const Node *calleeNode = find(name);
    if (std::optional<Want> want =
            decide(call, requester, callee, calleeNode, *s.times, *s.holds)) {
      FailureOr<Node *> node = request(s, fn, *want, call);
      if (failed(node))
        return failure();
      if (*node) {
        // A call's effects are its callee's entry, which a node has once it
        // is final; until then the call may do anything.
        idr::EffectAttr effects;
        {
          std::lock_guard lock(s.mutex);
          if (idr::FuncOp made = (*node)->fn; made && s.schedule->isFinal(made))
            effects = made.getEffectsAttr();
        }
        FlatSymbolRefAttr target = (*node)->name;
        auto transform = [&] { redirect(rewriter, call, target, effects, *want); };
        bool done = want->consumer
                        ? support::perform<RaiseAction>(call, transform)
                        : support::perform<SpecializeCloneAction>(call, transform);
        if (done) {
          ++redirected;
          changed = true;
          continue;
        }
      }
    }
    // A call of a node takes the node's entry once the node is final.
    if (calleeNode && call.getEffectsAttr() != callee.getEffectsAttr()) {
      rewriter.modifyOpInPlace(call, [&] { call.setEffectsAttr(callee.getEffectsAttr()); });
      changed = true;
    }
  }
  return success();
}

} // namespace idr::specialize
