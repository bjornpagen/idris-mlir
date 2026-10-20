// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ready set: one node per function of the program, the components of
// its call graph, callees first, and what each component waits on. Built
// once, on the pass thread, before the first wave.
//
// A function waits on what it calls. Once the program is first-order that
// is all it runs, a force being a call of its memo sum's dispatch function,
// so upstream's call graph is the whole graph: the components and their
// order are its cycles of calls (CallCycles), a function of the program
// alone.

#include "idr/Transforms/Optimize.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <utility>

using namespace mlir;

namespace idr::optimize {

ReadySet::ReadySet(ProgramOp program, const CallCycles &cycles) {
  SmallVector<FuncOp> fns(program.getOps<FuncOp>());
  unsigned n = static_cast<unsigned>(fns.size());

  // The callees of every function now, frozen for the run: each body is
  // walked on a worker into its own slot; what is read off them in program
  // order is the same however many threads walked.
  SmallVector<SmallVector<StringAttr>> callees(n);
  parallelFor(program.getContext(), 0, n, [&](size_t at) {
    fns[at].getBody().walk([&](CallOp call) { callees[at].push_back(call.getCalleeAttr().getAttr()); });
  });
  // calls(f): every call site naming f.
  llvm::DenseMap<StringAttr, unsigned> calls;
  for (const SmallVector<StringAttr> &slot : callees)
    for (StringAttr callee : slot)
      ++calls[callee];

  // The components first, so that each node is made in its own; its
  // members come in program order. A first-order program's callables are
  // its functions.
  llvm::DenseMap<Operation *, Scc *> sccOf;
  for (const CallCycles::Component &part : cycles.components()) {
    auto scc = std::make_unique<Scc>();
    scc->order = static_cast<unsigned>(sccs.size());
    for (Operation *fn : part)
      sccOf.try_emplace(fn, scc.get());
    sccs.push_back(std::move(scc));
  }
  for (FuncOp fn : fns) {
    Scc &scc = *sccOf.at(fn);
    auto node = std::make_unique<Node>(fn, Node::Held{calls.lookup(fn.getSymNameAttr())}, scc);
    scc.members.push_back(node.get());
    byName.try_emplace(fn.getSymNameAttr(), node.get());
    all.push_back(std::move(node));
  }
  // Each edge between two components once, in program order of its caller
  // and walk order of its calls.
  llvm::DenseSet<std::pair<Scc *, Scc *>> linked;
  for (auto [fn, slot] : llvm::zip_equal(fns, callees)) {
    Scc *from = sccOf.at(fn);
    for (StringAttr callee : slot) {
      Scc *into = byName.at(callee)->scc;
      if (from == into || !linked.insert({from, into}).second)
        continue;
      into->callers.push_back(from->members.front());
      ++from->unfinishedCallees;
    }
  }
}

ReadySet::~ReadySet() = default;

// A node the table made and has not placed is no node of the ready set yet,
// and not final.
std::optional<specialize::KnownCallee> ReadySet::finalCallee(StringAttr name) const {
  const Node *node = byName.lookup(name);
  if (!node || !node->isFinal())
    return std::nullopt;
  return specialize::KnownCallee{node->fn, node->published->times};
}

std::optional<specialize::KnownCallee> ReadySet::knownCallee(StringAttr reader,
                                                             StringAttr name) const {
  const Node *from = byName.lookup(reader);
  if (!from)
    return std::nullopt;
  return std::visit(
      llvm::makeVisitor(
          [](const Final &known) -> std::optional<specialize::KnownCallee> {
            return specialize::KnownCallee{known.fn, known.summary.times};
          },
          [](const Sibling &sibling) -> std::optional<specialize::KnownCallee> {
            return specialize::KnownCallee{sibling.fn, sibling.solved.times};
          },
          [](Pending) -> std::optional<specialize::KnownCallee> { return std::nullopt; }),
      callee(*from, name));
}

bool ReadySet::sameComponent(StringAttr a, StringAttr b) const {
  return byName.at(a)->sharesComponentWith(*byName.at(b));
}

// A final callee's is its summary; a callee of the reader's own component
// taken up, what the component solved when it took it up; anything else is
// pending. A call the reader's redirect step made of a node the table made
// in this wave names no node of the ready set until the wave ends: the
// steps after the redirect read that call, and it is pending.
Callee ReadySet::callee(const Node &reader, StringAttr name) const {
  const Node *found = byName.lookup(name);
  if (!found)
    return Pending{};
  const Node &node = *found;
  if (node.isFinal())
    return Final{node.fn, *node.published};
  if (!node.sharesComponentWith(reader))
    return Pending{};
  return std::visit(llvm::makeVisitor([](const Node::Waiting &) -> Callee { return Pending{}; },
                                      [&](const Node::Parked &parked) -> Callee {
                                        return Sibling{node.fn, parked.solved};
                                      },
                                      [&](const Node::Done &done) -> Callee {
                                        return Sibling{node.fn, done.solved};
                                      }),
                    node.state);
}

} // namespace idr::optimize
