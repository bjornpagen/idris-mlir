// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize's scheduler: the waves that run the schedule (Optimize.h),
// each component's turn on a worker and what is settled between waves on
// the pass thread. Read by idr-optimize's own units alone.
#ifndef IDR_TRANSFORMS_OPTIMIZESCHEDULER_H
#define IDR_TRANSFORMS_OPTIMIZESCHEDULER_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SmallVector.h"

#include <atomic>
#include <cstdint>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace idr::optimize {

// The start of one function's work in idr-optimize, once per function;
// its IR unit is the function. A debug counter may skip it, and a skipped
// function stays as it was.
struct NodeAction : support::TaggedAction<NodeAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-optimize-node";
};

// One component's turn in a wave: the members it takes up, those it
// resumes, and what it left for the pass thread to settle.
struct Turn {
  explicit Turn(unsigned component) : component(component) {}

  unsigned component;
  llvm::SmallVector<FunctionId> starters, resumed;
  // The copies this turn built.
  llvm::SmallVector<specialize::Node *> built;
  // Each member it parked, with the batch it asked for and could not have.
  llvm::SmallVector<std::pair<FunctionId, llvm::SmallVector<specialize::Node *>>> parked;
  // Whether every member of the component is done, so it becomes final.
  enum class Ends : bool { No, Yes } ends = Ends::No;
};

// One start or resume of a member, what a wave runs. A member starts once
// and resumes once per park, a park named by the first copy of the batch it
// waits for, which no later batch holds: so the steps are finitely many,
// as the copies and their requests are.
struct Start {
  FunctionId member;
};
struct Resume {
  FunctionId member;
  specialize::Node *on;
};
using Step = std::variant<Start, Resume>;

// The pass, and its own way of running a pipeline on an op nested under
// its own, which only a pass may (Optimize.cpp defines both).
struct OptimizePass;
mlir::LogicalResult runNested(OptimizePass &pass, mlir::OpPassManager &pm, mlir::Operation *op);

// Whether a member's batch left it parked on a copy not yet final.
enum class Outcome : bool { Continues, Parks };

// The waves. A wave is every step queued: the turn of every component
// whose callees are final and whose members wait on nothing, run in
// parallel as their arenas admit. Between waves, on the pass thread with no
// turn running, made copies go into the program, finished components
// become final and publish their summaries, waits are counted, components
// a wait would close a cycle through are merged, and the steps that can go
// on are queued. Every turn reads a fixed set of final functions, so the
// output is the same at any thread count, and so is the work of the solve
// of what each finished component gives back, added to `spent`.
class Scheduler {
public:
  Scheduler(OptimizePass &pass, Schedule &schedule, specialize::Nodes &nodes, const InnerCounts &counts,
            mlir::AnalysisManager am, Admission &admission, solver::Work &spent);

  // Failure when a turn failed, having emitted its diagnostic, or when a
  // function was left not final, an internal error.
  mlir::LogicalResult run();
  std::uint64_t made() const { return numMade; }

private:
  mlir::LogicalResult turn(Turn &turn);
  void takeUp(llvm::ArrayRef<FunctionId> starters);
  mlir::LogicalResult runMember(FunctionId member, Turn &turn);
  mlir::FailureOr<Outcome> parks(FunctionId member, llvm::SmallVector<specialize::Node *> asked,
                                 Turn &turn);
  mlir::LogicalResult round(FunctionId member);
  mlir::LogicalResult build(llvm::ArrayRef<specialize::Node *> asked, FunctionId claimant,
                            Turn &turn);

  // Between waves (Waves.cpp).
  void enable(llvm::SmallVectorImpl<Step> &ready);
  llvm::SmallVector<Turn, 0> gather(llvm::ArrayRef<Step> ready);
  void settle(llvm::MutableArrayRef<Turn> wave);
  FunctionId insert(specialize::Node *made);
  void finalize(unsigned component);
  void want(FunctionId requester, FunctionId target);

  OptimizePass &pass;
  Schedule &schedule;
  specialize::Nodes &nodes;
  const InnerCounts &counts;
  mlir::AnalysisManager am;
  Admission &admission;
  solver::Work &spent;

  // Copies of the inner pipeline, one per worker that runs one.
  mlir::OpPassManager inner;
  std::mutex pipelinesMutex;
  std::vector<std::unique_ptr<mlir::OpPassManager>> pipelines;
  llvm::SmallVector<mlir::OpPassManager *> idle;

  // The components whose turn may come: queued when the count of their
  // callees not final reaches zero, when a wait of one of their members is
  // met, and when they are made or merged; each read once per wave.
  llvm::SmallVector<unsigned> check;

  std::uint64_t numMade = 0;
};

// The end of a component: its members' binding times are published with
// their constants and bodies, their unread parameters are dropped (Demand
// .cpp), and the rows and the facts the component's final bodies state are
// derived.
void dropUnread(Schedule &schedule, llvm::ArrayRef<FunctionId> members);

// The end of the run, every function final and no turn running: the
// results no caller reads (Results.cpp), then the labels' captures nothing
// reads (Captures.cpp), each dropped from the whole program.
void dropDeadResults(Schedule &schedule);
void narrowCaptures(Schedule &schedule);

// What `fn` gives back once the arguments and results `arguments` and
// `results` hold are dropped: the entries that name one go, and the
// others count the positions left before theirs.
void renumberGivenBack(FuncOp fn, const llvm::BitVector &arguments, const llvm::BitVector &results);

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_OPTIMIZESCHEDULER_H
