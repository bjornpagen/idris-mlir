// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize, the first-order optimizer: one bottom-up ready set over the
// components of the call graph, run in waves. A function is taken up once
// every component it calls into is final; it inlines its calls into final
// callees, runs the inner pipeline once, and runs both again for each
// batch of specialization nodes its pipeline requested. What a final
// function tells its callers is one Summary on its node, written once; the
// scheduler that runs the waves is OptimizeScheduler.h's. And idr-contify,
// which runs before it. (The ready set is Mojo's AutomaticInline design
// rebuilt on upstream's call graph and MLIR's thread pool.)
#ifndef IDR_TRANSFORMS_OPTIMIZE_H
#define IDR_TRANSFORMS_OPTIMIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Constants.h"
#include "idr/Analysis/Inline.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace idr {

#define GEN_PASS_DECL_IDROPTIMIZE
#define GEN_PASS_DECL_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"

namespace optimize {

struct Scc;

// What a component's turn solves for a function when it takes it up: the
// argument it gives back, solved over the members taken up with it, and
// the binding time of each parameter, from the component's bodies or, for
// a made node, its owner's by its key. Written once, by that turn, into
// the node's state.
struct Solved {
  std::optional<unsigned> givesBack;
  llvm::SmallVector<BindingTime> times;
};

// What a function tells its callers: written once, whole, when its
// component becomes final, and never again. Final is set between waves, so
// the wave barrier orders every read after the write, and nothing needs a
// lock.
struct Summary {
  // What a run may do: the component's entry from its final bodies, also
  // written on the function and on every call of it as their `effects`.
  idr::Effect effects;
  // What it solved when its component took it up.
  std::optional<unsigned> givesBack;
  llvm::SmallVector<BindingTime> times;
  // What a call returns, read from the final body.
  ConstantResults constants;
  // The inline verdict and size, decided on the final body.
  inlining::Facts facts;
};

// A callee as the ready set answers it to a reader, one of three: final,
// with its function and summary, which no one writes again; a sibling, of
// the reader's own component and taken up, with its function, which only
// the component's turn writes, and what its turn solved; or pending, not
// final and nothing yet known of it, which a reader reads nothing of.
struct Final {
  idr::FuncOp fn;
  const Summary &summary;
};
struct Sibling {
  idr::FuncOp fn;
  const Solved &solved;
};
struct Pending {};
using Callee = std::variant<Final, Sibling, Pending>;

// The argument a callee gives back as a reader sees it: a final callee's
// summary's, a sibling's solve's, nothing of a pending one.
inline std::optional<unsigned> givenBack(const Callee &callee) {
  return std::visit(llvm::makeVisitor([](const Final &known) { return known.summary.givesBack; },
                                      [](const Sibling &sibling) { return sibling.solved.givesBack; },
                                      [](Pending) { return std::optional<unsigned>(); }),
                    callee);
}

// One function of the ready set: a function the program held when
// idr-optimize began, or a specialization node it made.
class Node {
  // Where it comes from: a function the program held, with the program's
  // idr.call sites naming it when idr-optimize began; or a node the table
  // built, called from the one request that made it, with the binding
  // times its build inherited from its owner by its key until its
  // component's turn takes them up.
  struct Held {
    unsigned calls;
  };
  struct Made {
    llvm::SmallVector<BindingTime> times;
    // Whether it is a step of a recursion on static data: the function the
    // program held that it stands for is on a cycle of calls, and its key
    // fixes no closure, or one of a label of that recursion
    // (Scheduler::stepOfRecursion).
    bool stepOfRecursion = false;
  };

public:
  using Origin = std::variant<Held, Made>;

  // Only the ready set and its scheduler can name an origin.
  Node(idr::FuncOp fn, Origin origin, Scc &scc) : fn(fn), origin(std::move(origin)), scc(&scc) {}

  // The function, which a node keeps from when it is made. A made node is
  // in the ready set only once the node table built it.
  idr::FuncOp fn;

  // Whether its component is final: its summary is published and nothing
  // writes the function again. Published between waves only, so it is the
  // same for every reader of a wave.
  bool isFinal() const { return published.has_value(); }
  // Whether it and `other` are one component. Every node holds its
  // component, and merges happen between waves only, so a worker may ask.
  bool sharesComponentWith(const Node &other) const { return scc == other.scc; }

private:
  friend class ReadySet;
  friend class Scheduler;

  // One not taken up; one parked after asking for a batch of nodes, the
  // first of which names the park; or one taken up and not parked, done
  // once its turn ends. A turn writes what it solved into the state when it
  // takes the member up, and the state holds it from then on. A member's
  // turn writes its state; the rest changes between waves.
  struct Waiting {};
  struct Parked {
    specialize::Node *on;
    Solved solved;
  };
  struct Done {
    Solved solved;
  };
  using State = std::variant<Waiting, Parked, Done>;

  // Whether it still waits: on a node that is neither final nor of its own
  // component. A wait is met by what happens to its target, so nothing
  // takes it away.
  bool waiting() const {
    return llvm::any_of(waitsOn, [&](const Node *target) {
      return !target->isFinal() && target->scc != scc;
    });
  }

  // Whether the inline rule keeps its calls, as it keeps those of a function
  // on a cycle: a node made of a recursive function on static data is one
  // step of that recursion, and inlining it hands its caller the next
  // step's static arguments, which ask for the next node, so the recursion
  // would unroll into its callers up to the caller cap. A node that applies
  // known closures of labels outside the recursion is no such step.
  bool stepOfRecursion() const {
    const auto *made = std::get_if<Made>(&origin);
    return made && made->stepOfRecursion;
  }

  // The call sites the inline rule weighs.
  unsigned calls() const {
    return std::visit(llvm::makeVisitor([](const Held &held) { return held.calls; },
                                        [](const Made &) { return 1u; }),
                      origin);
  }

  Origin origin;
  // Written by its own component's turns, each on one worker and in waves
  // that the barrier between them orders, and read by those turns alone.
  State state = Waiting{};
  // Its summary: written once, between waves, when its component becomes
  // final, and read by every worker of the waves after. No worker writes it
  // while another reads it. Final and not final are what every reader asks
  // first, apart from the turn's state.
  std::optional<Summary> published;
  // Its component; a merge moves it into the one merged into.
  Scc *scc;
  // What it asked for or calls, each once, met or not.
  llvm::SmallVector<Node *> waitsOn;
};

// A component of the ready set's graph, callees first. A component grows
// when a node would wait on one that waits, through requests and calls, on
// it; the one merged into keeps the members, and the other is gone.
struct Scc {
  // Its place among the ready set's components, the order of a wave's
  // turns: distinct for every component the run made.
  unsigned order = 0;
  // Program order; a merge appends the merged members.
  llvm::SmallVector<Node *> members;
  // A member of each component with a call into this one, once per call
  // graph edge between components; a merge appends the merged one's. A
  // member always holds its component, so a caller's is found through it.
  llvm::SmallVector<Node *> callers;
  unsigned unfinishedCallees = 0;
};

// The ready set of one run of idr-optimize over `program`, the node table's
// view of the schedule, and where the steps of the inner pipeline read the
// summaries. Its maps change only between waves, so every reader may be
// called from any worker of a wave.
class ReadySet final : public specialize::Schedule {
public:
  // Its components are the cycles of calls of `program`, callees first.
  ReadySet(idr::ProgramOp program, const CallCycles &cycles);
  ~ReadySet() override;

  // The node of the function named `name` the program holds; null for none.
  Node *nodeOf(mlir::StringAttr name) const { return byName.lookup(name); }
  // How many nodes it holds: the program's functions and the made nodes.
  size_t nodeCount() const { return all.size(); }
  Node *held(mlir::StringAttr name) const override { return nodeOf(name); }
  std::optional<specialize::FinalCallee> finalCallee(mlir::StringAttr name) const override;
  bool sameComponent(mlir::StringAttr a, mlir::StringAttr b) const override;

  // The callee named `name` of a call in `reader`'s body, as `reader` sees
  // it: a function of the program, or a node the table made in this wave,
  // not yet placed and pending.
  Callee callee(const Node &reader, mlir::StringAttr name) const;

private:
  friend class Scheduler;
  std::vector<std::unique_ptr<Node>> all;
  // Every component but those merged into another.
  std::vector<std::unique_ptr<Scc>> sccs;
  llvm::DenseMap<mlir::StringAttr, Node *> byName;
};

// The statistics of idr-optimize its inner pipeline's steps count into:
// every copy of the pipeline counts into these, so a count is the run's
// whichever worker made it.
struct InnerCounts {
  mlir::Pass::Statistic &identityCalls;
  mlir::Pass::Statistic &redirected;
  mlir::Pass::Statistic &constants;
  // What the inner pipeline's cse counted: its statistics are its own on
  // each copy of the pipeline, and the scheduler adds them here once the
  // waves end (addInnerStatistics).
  mlir::Pass::Statistic &cseMerged;
  mlir::Pass::Statistic &cseErased;
};

// What the inner pipeline's steps read of one run of idr-optimize, and where
// they count. Each step is given its part when it is made, so a step exists
// only within a run.
struct InnerRun {
  const ReadySet &set;
  const specialize::Nodes &nodes;
  const InnerCounts &counts;
};

// The inner per-function pipeline of one run, run once per node and again
// by the node's loop, into `pm`, a manager on idr.func.
void buildInnerPipeline(mlir::OpPassManager &pm, const InnerRun &run);

} // namespace optimize
} // namespace idr

#endif // IDR_TRANSFORMS_OPTIMIZE_H
