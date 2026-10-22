// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize, the first-order optimizer, a fixed sequence of phases:
//   - specialize, bottom-up over the components of the program graph: a
//     function is taken up once every component it calls into is final,
//     and runs rounds of its inner pipeline (the redirect to the copies its
//     calls' keys name, leaf inlining, the e-graph, constants) until a
//     round asks for no copy and inlines no leaf; the copies it asked for
//     are made, numbered and taken up before it goes on; then, every
//     function final, the results no caller reads and the labels' captures
//     nothing reads go from the whole program, and each copy says what
//     kind of copy it is;
//   - inline, once, on the final graph, with every call site counted, on
//     upstream's inliner, a callee's verdict its profitability and the
//     e-graph its simplification;
//   - contify again, then the e-graph once more over every function.
// What a final function tells its callers is one summary, written once.
// And idr-contify, which runs before it and inside it.
#ifndef IDR_TRANSFORMS_OPTIMIZE_H
#define IDR_TRANSFORMS_OPTIMIZE_H

#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/Constants.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Inline.h"
#include "idr/Transforms/SpecializeState.h"

#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/SmallVector.h"

#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace idr {

#define GEN_PASS_DECL_IDROPTIMIZE
#define GEN_PASS_DECL_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"

namespace optimize {

using solver::FunctionId;

// What a component's turn solves for a member when it takes it up: each
// parameter's binding time, from the component's bodies or, for a copy,
// its owner's by its key. Written once, by that turn.
struct Solved {
  llvm::SmallVector<BindingTime> times;
};

// What a final function tells its callers, written once, whole, when its
// component becomes final, between waves, so the barrier orders every read
// after the write and nothing needs a lock.
struct Summary {
  llvm::SmallVector<BindingTime> times;
  // What a call of it returns, read from its final body.
  ConstantResults constants;
  // Its size in ops and whether it calls anything, which leaf inlining
  // reads; the weighed verdict is decided once every call site is known.
  inlining::Body body;
};

// A function's phase in the schedule, one at a time: not taken up; parked
// on the first copy of a batch it asked for and cannot have yet; taken up
// and running or done; final, with what it tells its callers.
struct Waiting {};
struct Parked {
  specialize::Node *on;
  Solved solved;
};
struct Done {
  Solved solved;
};
struct Final {
  Summary summary;
};
using Phase = std::variant<Waiting, Parked, Done, Final>;

// What a reader may read of a function: its op and its parameters'
// binding times.
struct Readable {
  FuncOp fn;
  llvm::ArrayRef<BindingTime> times;
};

// The schedule of one run of idr-optimize over the thawed program graph:
// each function's phase, its component, the counts the waves are driven
// by, and the requester state each member's turn owns. Its tables change
// only between waves, so every reader may be called from any worker of a
// wave; a member's own phase and requester state are written by its turn
// alone.
class Schedule {
public:
  // Takes what the editor does not hold out of `graph` (its components,
  // its callers, which functions are on a cycle), then thaws it.
  Schedule(ProgramOp program, solver::ProgramGraph &graph);

  // The table whose copies are pending until placed: a call of one names
  // no function of the schedule until the wave that made it ends.
  void attach(specialize::Nodes &table) { nodes = &table; }

  // A function by its id; resolving a callee or a label is the graph
  // editor's (Editor::id, and Editor::find, none for a copy made in this
  // wave and not yet placed).
  FuncOp function(FunctionId fn) const { return members[fn.index()].fn; }
  mlir::StringAttr symbolOf(FunctionId fn) const { return function(fn).getSymNameAttr(); }

  // The function the program held that `fn` stands for, back through the
  // copies it was made from; whether that one is on a cycle of calls; and
  // whether two functions are one component of the schedule now.
  FunctionId originOf(FunctionId fn) const { return members[fn.index()].origin; }
  bool onCycle(FunctionId fn) const { return cyclic.test(originOf(fn).index()); }
  bool sameComponent(FunctionId a, FunctionId b) const {
    return components.findLeader(a.index()) == components.findLeader(b.index());
  }

  // `fn` once final; `target` as `reader` may read it: final, or of
  // `reader`'s own component and taken up, which only `reader`'s turn
  // writes. The grant of a copy checked the second already.
  std::optional<Readable> final(FunctionId fn) const;
  Readable readable(FunctionId reader, FunctionId target) const;
  const Summary *summaryOf(FunctionId fn) const;

  specialize::Requester &requesterOf(FunctionId fn) { return members[fn.index()].requests; }

  // The leaves the member's last round inlined, which its turn alone
  // writes and reads: a round that inlined one goes on to another.
  void noteLeaves(FunctionId fn, unsigned inlined) { members[fn.index()].leaves += inlined; }
  unsigned takeLeaves(FunctionId fn) { return std::exchange(members[fn.index()].leaves, 0); }

  // The functions with a call of `fn`, as the program held them and as
  // each copy placed since added its own.
  llvm::ArrayRef<FunctionId> callersOf(FunctionId fn) const { return members[fn.index()].callers; }
  // Whether a family's label names `fn`: its leading parameters are that
  // label's captures, the family's fields. A copy is never one.
  bool isLabel(FunctionId fn) const { return labelled.test(fn.index()); }

  ProgramOp program;

private:
  friend class Scheduler;
  friend void dropUnread(Schedule &schedule, llvm::ArrayRef<FunctionId> members);

  struct Member {
    FuncOp fn;
    // The copy it is, or none for a function the program held.
    specialize::Node *node = nullptr;
    FunctionId origin;
    // Its own id, which its place in the table is.
    FunctionId self;
    Phase phase = Waiting{};
    specialize::Requester requests;
    // A copy's binding times, its owner's by its key, until its turn takes
    // them up.
    llvm::SmallVector<BindingTime> inherited;
    llvm::SmallVector<FunctionId, 2> callers;
    // What it waits on, each once: the copies it asked for and the
    // functions a copy calls; and who waits on it. A wait is met once its
    // target is final or of its own component; `unmet` counts the rest,
    // recounted when a merge changes which are of its component.
    llvm::SmallVector<FunctionId, 2> waitsOn;
    llvm::SmallVector<FunctionId, 2> waiters;
    unsigned unmet = 0;
    unsigned leaves = 0;
  };

  specialize::Nodes *nodes = nullptr;
  // Each function's member, by its id: ids are dense, and a copy placed
  // between waves takes the next one the editor mints.
  footprint::Vector<Member> members;
  llvm::BitVector cyclic;
  // The functions a family's label names, by id; each copy placed adds a
  // bit, clear.
  llvm::BitVector labelled;
  // The components: each function's class, merged where a wait closes a
  // cycle; per class leader, by the leader's id, its callees not yet final
  // and its members, in id order. A function that leads no class has no
  // members and counts nothing.
  llvm::IntEqClasses components;
  footprint::Vector<unsigned> unfinished;
  footprint::Vector<footprint::Vector<FunctionId>> byComponent;
  // The members some of whose waits are not met, by id: the only ones a
  // cycle of waits can run through.
  llvm::DenseSet<unsigned> blocked;

  // Reads what the editor will not hold into the tables above, then thaws
  // the graph: initialized last, once the tables exist.
  solver::Editor takeOut(solver::ProgramGraph &frozen);

public:
  solver::Editor graph;
  // What each final function gives back, which the e-graph of every later
  // turn reads to replace a floating call by its argument: written between
  // waves, when a component becomes final.
  egraph::CalleeFacts callees{graph};
};

// The statistics idr-optimize's inner pipeline counts into, whichever copy
// of the pipeline counted.
struct InnerCounts {
  mlir::Pass::Statistic &redirected;
  mlir::Pass::Statistic &inlinedLeaves;
  mlir::Pass::Statistic &constants;
};

// The inner pipeline of one run, on idr.func: the redirect first, so the
// e-graph sees a combinator called on known closures as a call of its
// copy; then leaf inlining, the e-graph, and constants last, so a final
// body states its summary.
void buildInnerPipeline(mlir::OpPassManager &pm, Schedule &schedule, specialize::Nodes &nodes,
                        const InnerCounts &counts);

// The memory the e-graphs of the functions in flight may take together:
// the host's, read once. A function enters a run of the pipeline only
// while its arena fits beside those running, so a small host compiles more
// slowly and never differently; one whose arena alone exceeds it ends the
// compiler through its one out-of-memory handler.
class Admission {
public:
  explicit Admission(std::uint64_t budget) : budget(budget) {}
  // Blocks until `bytes` fit; then they are in flight.
  void enter(std::uint64_t bytes);
  void leave(std::uint64_t bytes);

private:
  std::uint64_t budget;
  std::uint64_t inFlight = 0;
  std::mutex mutex;
  std::condition_variable freed;
};

} // namespace optimize
} // namespace idr

#endif // IDR_TRANSFORMS_OPTIMIZE_H
