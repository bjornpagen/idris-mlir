// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The nodes of one run of idr-optimize, by key, and their phases: each
// made by the first request of its key (Requests.cpp), claimed by one
// worker, built, and placed in the program.
//
// A node is built once, by the worker that claims it, from its key and its
// owner's final body alone, its binding times its owner's by its key. The
// ready set puts it into the program after its owner, among the nodes
// there by name; its own turns redirect its calls, the first of them a
// call of its owner with its own key into its own recursion.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Transforms/SpecializeState.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <mutex>
#include <optional>

using namespace mlir;

namespace idr::specialize {

using namespace detail;

namespace {

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

} // namespace idr::specialize
